#include <kernel/console.h>
#include <kernel/memory_layout.h>
#include <kernel/pmm.h>
#include <kernel/string.h>
#include <kernel/vmm.h>

#define PAGE_ENTRY_PRESENT (1ULL << 0U)
#define PAGE_ENTRY_WRITE (1ULL << 1U)
#define PAGE_ENTRY_USER (1ULL << 2U)
#define PAGE_ENTRY_HUGE (1ULL << 7U)
#define PAGE_ENTRY_NX (1ULL << 63U)
#define PAGE_ADDRESS_MASK 0x000ffffffffff000ULL
#define HUGE_PAGE_SIZE 0x200000ULL
#define EFER_MSR 0xc0000080U
#define EFER_NXE (1ULL << 11U)
#define CR0_WRITE_PROTECT (1ULL << 16U)

extern u8 __kernel_virtual_start[];
extern u8 __text_start[];
extern u8 __text_end[];
extern u8 __rodata_start[];
extern u8 __rodata_end[];
extern u8 __data_start[];
extern u8 __data_end[];
extern u8 __bss_section_start[];
extern u8 __bss_section_end[];

static u64 root_physical;
static bool final_tables_active;
static u64 kernel_virtual_start;
static u64 kernel_physical_start;
static u64 kernel_physical_end;

static u64 read_msr(u32 msr)
{
    u32 low;
    u32 high;

    __asm__ volatile("rdmsr" : "=a"(low), "=d"(high) : "c"(msr));
    return ((u64)high << 32U) | low;
}

static void write_msr(u32 msr, u64 value)
{
    __asm__ volatile("wrmsr" : : "c"(msr), "a"((u32)value),
                     "d"((u32)(value >> 32U)) : "memory");
}

static bool cpu_has_nx(void)
{
    u32 eax = 0x80000000U;
    u32 ebx;
    u32 ecx = 0U;
    u32 edx;

    __asm__ volatile("cpuid"
                     : "+a"(eax), "=b"(ebx), "+c"(ecx), "=d"(edx));
    if (eax < 0x80000001U) {
        return false;
    }
    eax = 0x80000001U;
    ecx = 0U;
    __asm__ volatile("cpuid"
                     : "+a"(eax), "=b"(ebx), "+c"(ecx), "=d"(edx));
    return (edx & (1U << 20U)) != 0U;
}

static u64 *table_pointer(u64 physical_address)
{
    if (final_tables_active) {
        return (u64 *)physical_to_virtual(physical_address);
    }
    return (u64 *)(uptr)physical_address;
}

static u64 allocate_table(void)
{
    u64 physical_address = page_alloc();

    memset(table_pointer(physical_address), 0, PAGE_SIZE);
    return physical_address;
}

static bool address_is_canonical(u64 address)
{
    u64 upper = address >> 48U;

    return upper == 0ULL || upper == 0xffffULL;
}

static u64 entry_from_flags(u64 physical_address, u64 flags)
{
    u64 entry = (physical_address & PAGE_ADDRESS_MASK) | PAGE_ENTRY_PRESENT;

    if ((flags & VM_WRITE) != 0ULL) {
        entry |= PAGE_ENTRY_WRITE;
    }
    if ((flags & VM_USER) != 0ULL) {
        entry |= PAGE_ENTRY_USER;
    }
    if ((flags & VM_EXEC) == 0ULL) {
        entry |= PAGE_ENTRY_NX;
    }
    return entry;
}

static u64 flags_from_entry(u64 entry)
{
    u64 flags = 0ULL;

    if ((entry & PAGE_ENTRY_WRITE) != 0ULL) {
        flags |= VM_WRITE;
    }
    if ((entry & PAGE_ENTRY_USER) != 0ULL) {
        flags |= VM_USER;
    }
    if ((entry & PAGE_ENTRY_NX) == 0ULL) {
        flags |= VM_EXEC;
    }
    return flags;
}

static u64 *walk_to_pte(u64 virtual_address, bool create, u64 flags)
{
    const u16 indices[4] = {
        (u16)((virtual_address >> 39U) & 0x1ffU),
        (u16)((virtual_address >> 30U) & 0x1ffU),
        (u16)((virtual_address >> 21U) & 0x1ffU),
        (u16)((virtual_address >> 12U) & 0x1ffU)
    };
    u64 table_physical = root_physical;
    u32 level;

    for (level = 0U; level < 3U; ++level) {
        u64 *table = table_pointer(table_physical);
        u64 entry = table[indices[level]];

        if ((entry & PAGE_ENTRY_PRESENT) == 0ULL) {
            u64 child;

            if (!create) {
                return (u64 *)0;
            }
            child = allocate_table();
            entry = child | PAGE_ENTRY_PRESENT | PAGE_ENTRY_WRITE;
            if ((flags & VM_USER) != 0ULL) {
                entry |= PAGE_ENTRY_USER;
            }
            table[indices[level]] = entry;
        } else if ((entry & PAGE_ENTRY_HUGE) != 0ULL) {
            return (u64 *)0;
        } else if ((flags & VM_USER) != 0ULL) {
            table[indices[level]] |= PAGE_ENTRY_USER;
        }
        table_physical = entry & PAGE_ADDRESS_MASK;
    }
    return &table_pointer(table_physical)[indices[3]];
}

static bool map_page_internal(u64 virtual_address, u64 physical_address, u64 flags)
{
    u64 *entry;

    if ((virtual_address & PAGE_MASK) != 0ULL ||
        (physical_address & PAGE_MASK) != 0ULL ||
        !address_is_canonical(virtual_address)) {
        return false;
    }
    entry = walk_to_pte(virtual_address, true, flags);
    if (entry == (u64 *)0 || (*entry & PAGE_ENTRY_PRESENT) != 0ULL) {
        return false;
    }
    *entry = entry_from_flags(physical_address, flags);
    return true;
}

static bool map_huge_page(u64 virtual_address, u64 physical_address, u64 flags)
{
    const u16 pml4_index = (u16)((virtual_address >> 39U) & 0x1ffU);
    const u16 pdpt_index = (u16)((virtual_address >> 30U) & 0x1ffU);
    const u16 pd_index = (u16)((virtual_address >> 21U) & 0x1ffU);
    u64 *pml4 = table_pointer(root_physical);
    u64 pdpt_physical;
    u64 pd_physical;
    u64 *pdpt;
    u64 *pd;

    if ((virtual_address & (HUGE_PAGE_SIZE - 1ULL)) != 0ULL ||
        (physical_address & (HUGE_PAGE_SIZE - 1ULL)) != 0ULL) {
        return false;
    }
    if ((pml4[pml4_index] & PAGE_ENTRY_PRESENT) == 0ULL) {
        pdpt_physical = allocate_table();
        pml4[pml4_index] = pdpt_physical | PAGE_ENTRY_PRESENT | PAGE_ENTRY_WRITE;
    } else {
        pdpt_physical = pml4[pml4_index] & PAGE_ADDRESS_MASK;
    }
    pdpt = table_pointer(pdpt_physical);
    if ((pdpt[pdpt_index] & PAGE_ENTRY_PRESENT) == 0ULL) {
        pd_physical = allocate_table();
        pdpt[pdpt_index] = pd_physical | PAGE_ENTRY_PRESENT | PAGE_ENTRY_WRITE;
    } else {
        pd_physical = pdpt[pdpt_index] & PAGE_ADDRESS_MASK;
    }
    pd = table_pointer(pd_physical);
    if ((pd[pd_index] & PAGE_ENTRY_PRESENT) != 0ULL) {
        return false;
    }
    pd[pd_index] = entry_from_flags(physical_address, flags) | PAGE_ENTRY_HUGE;
    return true;
}

static u64 kernel_virtual_to_physical(u64 virtual_address)
{
    return kernel_physical_start + (virtual_address - kernel_virtual_start);
}

static u64 direct_map_flags(u64 physical_address)
{
    const u64 text_start = kernel_virtual_to_physical((u64)(uptr)__text_start);
    const u64 text_end = kernel_virtual_to_physical((u64)(uptr)__text_end);
    const u64 rodata_start = kernel_virtual_to_physical((u64)(uptr)__rodata_start);
    const u64 rodata_end = kernel_virtual_to_physical((u64)(uptr)__rodata_end);

    if ((physical_address >= text_start && physical_address < text_end) ||
        (physical_address >= rodata_start && physical_address < rodata_end)) {
        return 0ULL;
    }
    return VM_WRITE;
}

static void map_direct_region(void)
{
    u64 chunk;

    for (chunk = 0ULL; chunk < PMM_PHYSICAL_LIMIT; chunk += HUGE_PAGE_SIZE) {
        const bool overlaps_kernel =
            chunk < kernel_physical_end &&
            chunk + HUGE_PAGE_SIZE > kernel_physical_start;

        if (chunk == 0ULL || overlaps_kernel) {
            u64 physical_address;

            for (physical_address = chunk;
                 physical_address < chunk + HUGE_PAGE_SIZE;
                 physical_address += PAGE_SIZE) {
                if (!map_page_internal(PHYSICAL_DIRECT_MAP_BASE + physical_address,
                                       physical_address,
                                       direct_map_flags(physical_address))) {
                    panic("failed to map direct page 0x%llx", physical_address);
                }
            }
        } else if (!map_huge_page(PHYSICAL_DIRECT_MAP_BASE + chunk,
                                  chunk, VM_WRITE)) {
            panic("failed to map direct huge page 0x%llx", chunk);
        }
    }
}

static void map_kernel_range(u64 start, u64 end, u64 flags)
{
    u64 virtual_address;

    start = align_down_u64(start, PAGE_SIZE);
    end = align_up_u64(end, PAGE_SIZE);
    for (virtual_address = start; virtual_address < end;
         virtual_address += PAGE_SIZE) {
        if (!map_page_internal(virtual_address,
                               kernel_virtual_to_physical(virtual_address), flags)) {
            panic("failed to map kernel page 0x%llx", virtual_address);
        }
    }
}

void vmm_init(const struct boot_info *info)
{
    u64 cr0;

    if (final_tables_active || root_physical != 0ULL) {
        panic("VMM initialized twice");
    }
    if (!cpu_has_nx()) {
        panic("CPU does not support NX pages");
    }
    kernel_virtual_start = info->kernel_virt_start;
    kernel_physical_start = info->kernel_phys_start;
    kernel_physical_end = info->kernel_phys_end;
    root_physical = allocate_table();

    map_direct_region();
    map_kernel_range((u64)(uptr)__text_start, (u64)(uptr)__text_end, VM_EXEC);
    map_kernel_range((u64)(uptr)__rodata_start, (u64)(uptr)__rodata_end, 0ULL);
    map_kernel_range((u64)(uptr)__data_start, (u64)(uptr)__data_end, VM_WRITE);
    map_kernel_range((u64)(uptr)__bss_section_start,
                     (u64)(uptr)__bss_section_end, VM_WRITE);

    /* Console still uses the conventional VGA identity address. */
    if (!map_page_internal(0x000b8000ULL, 0x000b8000ULL, VM_WRITE)) {
        panic("failed to retain VGA identity mapping");
    }

    write_msr(EFER_MSR, read_msr(EFER_MSR) | EFER_NXE);
    __asm__ volatile("movq %%cr0, %0" : "=r"(cr0));
    cr0 |= CR0_WRITE_PROTECT;
    __asm__ volatile("movq %0, %%cr0" : : "r"(cr0) : "memory");
    __asm__ volatile("movq %0, %%cr3" : : "r"(root_physical) : "memory");
    final_tables_active = true;

    console_printf("K4:VMM READY cr3=0x%llx direct=0x%llx limit=0x%llx\n",
                   root_physical, PHYSICAL_DIRECT_MAP_BASE, PMM_PHYSICAL_LIMIT);
}

bool vm_map(u64 virtual_address, u64 physical_address, u64 flags)
{
    if (!final_tables_active) {
        panic("vm_map before vmm_init");
    }
    return map_page_internal(virtual_address, physical_address, flags);
}

bool vm_unmap(u64 virtual_address, u64 *physical_address)
{
    u64 *entry;

    if (!final_tables_active || (virtual_address & PAGE_MASK) != 0ULL) {
        return false;
    }
    entry = walk_to_pte(virtual_address, false, 0ULL);
    if (entry == (u64 *)0 || (*entry & PAGE_ENTRY_PRESENT) == 0ULL) {
        return false;
    }
    if (physical_address != (u64 *)0) {
        *physical_address = *entry & PAGE_ADDRESS_MASK;
    }
    *entry = 0ULL;
    __asm__ volatile("invlpg (%0)" : : "r"((uptr)virtual_address) : "memory");
    return true;
}

bool vm_protect(u64 virtual_address, u64 flags)
{
    u64 *entry;
    u64 physical_address;

    if (!final_tables_active || (virtual_address & PAGE_MASK) != 0ULL) {
        return false;
    }
    entry = walk_to_pte(virtual_address, false, flags);
    if (entry == (u64 *)0 || (*entry & PAGE_ENTRY_PRESENT) == 0ULL) {
        return false;
    }
    physical_address = *entry & PAGE_ADDRESS_MASK;
    *entry = entry_from_flags(physical_address, flags);
    __asm__ volatile("invlpg (%0)" : : "r"((uptr)virtual_address) : "memory");
    return true;
}

bool vm_translate(u64 virtual_address, u64 *physical_address, u64 *flags)
{
    u64 *entry;

    if (!final_tables_active) {
        return false;
    }
    entry = walk_to_pte(align_down_u64(virtual_address, PAGE_SIZE), false, 0ULL);
    if (entry == (u64 *)0 || (*entry & PAGE_ENTRY_PRESENT) == 0ULL) {
        return false;
    }
    if (physical_address != (u64 *)0) {
        *physical_address = (*entry & PAGE_ADDRESS_MASK) |
                            (virtual_address & PAGE_MASK);
    }
    if (flags != (u64 *)0) {
        *flags = flags_from_entry(*entry);
    }
    return true;
}

u64 vmm_root_physical(void)
{
    return root_physical;
}
