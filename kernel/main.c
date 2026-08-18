#include <kernel/boot_info.h>
#include <kernel/console.h>
#include <kernel/gdt.h>
#include <kernel/heap.h>
#include <kernel/interrupts.h>
#include <kernel/io.h>
#include <kernel/keyboard.h>
#include <kernel/memory_layout.h>
#include <kernel/pic.h>
#include <kernel/pmm.h>
#include <kernel/string.h>
#include <kernel/timer.h>
#include <kernel/types.h>
#include <kernel/vmm.h>

#ifndef KERNEL_TEST_MODE
#define KERNEL_TEST_MODE 0
#endif

#define KERNEL_TEST_NORMAL 0
#define KERNEL_TEST_DIVIDE_ERROR 1
#define KERNEL_TEST_UNMAPPED_PAGE 2
#define KERNEL_TEST_READ_ONLY_PAGE 3
#define KERNEL_TEST_NX_PAGE 4

__attribute__((section(".rodata.kernel_identity"), used))
const char kernel_identity[] = "tiny-linux-kernel M4";

static struct boot_info boot_info_copy;
static struct e820_entry e820_copy[BOOT_INFO_MAX_E820_ENTRIES];

static __attribute__((noreturn)) void halt_forever(void)
{
    interrupts_disable();
    for (;;) {
        cpu_halt();
    }
}

static void validate_boot_info(const struct boot_info *info)
{
    if (info == (const struct boot_info *)0 ||
        info->version != BOOT_INFO_VERSION ||
        info->size != sizeof(struct boot_info) ||
        info->e820_count == 0U ||
        info->e820_count > BOOT_INFO_MAX_E820_ENTRIES) {
        panic("invalid boot_info v1");
    }
}

static void print_boot_info(const struct boot_info *info)
{
    const struct e820_entry *entries =
        (const struct e820_entry *)(uptr)info->e820_entries;
    u32 index;

    console_printf("K2:BOOT drive=0x%x entries=0x%x\n",
                   (unsigned int)info->boot_drive,
                   (unsigned int)info->e820_count);
    console_printf("K2:KERNEL phys=0x%llx..0x%llx virt=0x%llx..0x%llx entry=0x%llx\n",
                   info->kernel_phys_start, info->kernel_phys_end,
                   info->kernel_virt_start, info->kernel_virt_end,
                   info->kernel_entry);

    for (index = 0U; index < info->e820_count; ++index) {
        console_printf("K2:E820[%u] base=0x%llx length=0x%llx type=0x%x attr=0x%x\n",
                       (unsigned int)index,
                       entries[index].base,
                       entries[index].length,
                       (unsigned int)entries[index].type,
                       (unsigned int)entries[index].attributes);
    }
}

static void preserve_boot_info(const struct boot_info *info)
{
    const struct e820_entry *entries =
        (const struct e820_entry *)(uptr)info->e820_entries;

    boot_info_copy = *info;
    memcpy(e820_copy, entries,
           (usize)info->e820_count * sizeof(struct e820_entry));
    boot_info_copy.e820_entries = (u64)(uptr)e820_copy;
}

static void runtime_self_test(void)
{
    static const u8 source[8] = {0U, 1U, 2U, 3U, 4U, 5U, 6U, 7U};
    static const u8 expected[8] = {0U, 0U, 1U, 2U, 3U, 4U, 5U, 6U};
    u8 bytes[8];
    usize index;

    memset(bytes, 0xa5, sizeof(bytes));
    memcpy(bytes, source, sizeof(bytes));
    memmove(bytes + 1U, bytes, sizeof(bytes) - 1U);
    for (index = 0U; index < sizeof(bytes); ++index) {
        if (bytes[index] != expected[index]) {
            panic("runtime memory self-test failed at %llu", (u64)index);
        }
    }
    if (strlen("M4") != 2U) {
        panic("runtime strlen self-test failed");
    }
    console_write("K3:RUNTIME OK\n");
}

static void memory_self_test(void)
{
    u64 pages[64];
    struct pmm_stats before;
    struct pmm_stats after;
    u64 mapped_physical;
    u64 mapped_flags;
    u64 physical_address;
    volatile u64 *mapped;
    u8 *large;
    u8 *reused;
    usize index;

    if (!vm_translate((u64)(uptr)memory_self_test,
                      &mapped_physical, &mapped_flags) ||
        (mapped_flags & VM_EXEC) == 0ULL ||
        (mapped_flags & VM_WRITE) != 0ULL ||
        !vm_translate((u64)(uptr)kernel_identity,
                      &mapped_physical, &mapped_flags) ||
        (mapped_flags & (VM_EXEC | VM_WRITE)) != 0ULL ||
        !vm_translate((u64)(uptr)&boot_info_copy,
                      &mapped_physical, &mapped_flags) ||
        (mapped_flags & VM_WRITE) == 0ULL ||
        (mapped_flags & VM_EXEC) != 0ULL ||
        vm_translate(0x00018000ULL, (u64 *)0, (u64 *)0) ||
        !vm_translate(0x000b8000ULL, &mapped_physical, &mapped_flags) ||
        mapped_physical != 0x000b8000ULL ||
        (mapped_flags & VM_WRITE) == 0ULL ||
        (mapped_flags & VM_EXEC) != 0ULL) {
        panic("final page-table permission self-test failed");
    }
    console_write("K4:VMM PERMS OK\n");

    before = pmm_get_stats();
    for (index = 0U; index < sizeof(pages) / sizeof(pages[0]); ++index) {
        usize previous;

        pages[index] = page_alloc();
        if ((pages[index] & PAGE_MASK) != 0ULL ||
            !pmm_page_is_managed(pages[index]) ||
            !pmm_page_is_allocated(pages[index])) {
            panic("PMM returned invalid page 0x%llx", pages[index]);
        }
        for (previous = 0U; previous < index; ++previous) {
            if (pages[previous] == pages[index]) {
                panic("PMM returned duplicate page 0x%llx", pages[index]);
            }
        }
    }
    for (index = 0U; index < sizeof(pages) / sizeof(pages[0]); ++index) {
        page_free(pages[index]);
        if (pmm_page_is_allocated(pages[index])) {
            panic("PMM page remained allocated after free");
        }
    }
    after = pmm_get_stats();
    if (after.free_pages != before.free_pages ||
        pmm_page_is_managed(PMM_PHYSICAL_LIMIT)) {
        panic("PMM stress test did not restore free count");
    }
    console_printf("K4:PMM STRESS OK pages=%u free=%llu\n",
                   (unsigned int)(sizeof(pages) / sizeof(pages[0])),
                   after.free_pages);

    physical_address = page_alloc();
    if (!vm_map(KERNEL_VM_TEST_BASE, physical_address, VM_WRITE)) {
        panic("VMM self-test map failed");
    }
    mapped = (volatile u64 *)(uptr)KERNEL_VM_TEST_BASE;
    mapped[0] = 0x1122334455667788ULL;
    mapped[PAGE_SIZE / sizeof(u64) - 1U] = 0x8877665544332211ULL;
    if (mapped[0] != 0x1122334455667788ULL ||
        mapped[PAGE_SIZE / sizeof(u64) - 1U] != 0x8877665544332211ULL ||
        !vm_translate(KERNEL_VM_TEST_BASE + 17ULL,
                      &mapped_physical, &mapped_flags) ||
        mapped_physical != physical_address + 17ULL ||
        (mapped_flags & VM_WRITE) == 0ULL) {
        panic("VMM self-test translation failed");
    }
    if (!vm_protect(KERNEL_VM_TEST_BASE, 0ULL) ||
        !vm_translate(KERNEL_VM_TEST_BASE,
                      &mapped_physical, &mapped_flags) ||
        (mapped_flags & (VM_WRITE | VM_EXEC)) != 0ULL) {
        panic("VMM self-test protect failed");
    }
    if (!vm_unmap(KERNEL_VM_TEST_BASE, &mapped_physical) ||
        mapped_physical != physical_address ||
        vm_translate(KERNEL_VM_TEST_BASE, (u64 *)0, (u64 *)0)) {
        panic("VMM self-test unmap failed");
    }
    page_free(physical_address);
    console_write("K4:VMM MAP/PROTECT OK\n");

    large = (u8 *)kmalloc(7000U);
    for (index = 0U; index < 7000U; ++index) {
        large[index] = (u8)(index ^ (index >> 8U));
    }
    for (index = 0U; index < 7000U; ++index) {
        if (large[index] != (u8)(index ^ (index >> 8U))) {
            panic("heap cross-page data mismatch at %llu", (u64)index);
        }
    }
    kfree(large);
    reused = (u8 *)kmalloc(6000U);
    if (reused != large) {
        panic("heap did not reuse released cross-page block");
    }
    kfree(reused);
    console_printf("K4:HEAP STRESS OK mapped_pages=%llu free=%llu\n",
                   heap_get_stats().mapped_pages,
                   heap_get_stats().free_bytes);
}

static __attribute__((noreturn, unused)) void trigger_divide_error(void)
{
    volatile u64 zero = 0U;

    console_write("K3:TRIGGER DIVIDE\n");
    __asm__ volatile(
        "xorq %%rdx, %%rdx\n"
        "divq %%rcx\n"
        :
        : "a"(1ULL), "c"(zero)
        : "rdx", "cc");
    panic("divide-error trigger returned");
}

static __attribute__((noreturn, unused)) void trigger_unmapped_page(void)
{
    volatile const u64 *const unmapped =
        (volatile const u64 *)(uptr)KERNEL_VM_TEST_BASE;
    volatile u64 value;

    console_write("K4:TRIGGER UNMAPPED\n");
    value = *unmapped;
    (void)value;
    panic("unmapped-page trigger returned");
}

static __attribute__((noreturn, unused)) void trigger_read_only_page(void)
{
    const u64 physical_address = page_alloc();
    volatile u64 *const page = (volatile u64 *)(uptr)KERNEL_VM_TEST_BASE;

    if (!vm_map(KERNEL_VM_TEST_BASE, physical_address, VM_WRITE)) {
        panic("read-only fault test map failed");
    }
    *page = 0x123456789abcdef0ULL;
    if (!vm_protect(KERNEL_VM_TEST_BASE, 0ULL)) {
        panic("read-only fault test protect failed");
    }
    console_write("K4:TRIGGER READONLY\n");
    *page = 0xfedcba9876543210ULL;
    panic("read-only trigger returned");
}

static __attribute__((noreturn, unused)) void trigger_nx_page(void)
{
    const u64 physical_address = page_alloc();
    volatile u8 *const page = (volatile u8 *)(uptr)KERNEL_VM_TEST_BASE;
    void (*function)(void);

    if (!vm_map(KERNEL_VM_TEST_BASE, physical_address, VM_WRITE)) {
        panic("NX fault test map failed");
    }
    page[0] = 0xc3U;
    function = (void (*)(void))(uptr)KERNEL_VM_TEST_BASE;
    console_write("K4:TRIGGER NX\n");
    function();
    panic("NX trigger returned");
}

static __attribute__((noreturn, unused)) void run_normal_interrupt_test(void)
{
    u64 first_tick;
    u64 second_tick;

    interrupts_enable();
    console_write("K3:READY\n");

    do {
        cpu_halt();
        first_tick = pit_ticks();
    } while (first_tick < 3U);

    do {
        cpu_halt();
        second_tick = pit_ticks();
    } while (second_tick < first_tick + 5U);

    console_printf("K3:TIMER OK first=%llu second=%llu hz=%u\n",
                   first_tick, second_tick, (unsigned int)PIT_TICKS_PER_SECOND);
    while (keyboard_event_count() == 0U) {
        cpu_halt();
    }
    console_printf("K3:KEYBOARD OK last=%c events=%llu\n",
                   keyboard_last_char(), keyboard_event_count());
    console_write("K4:HALT\n");
    console_write("K3:HALT\n");
    halt_forever();
}

__attribute__((noreturn))
void kernel_main(const struct boot_info *info)
{
    console_init();
    console_write("K2:LONG MODE OK\n");
    validate_boot_info(info);
    print_boot_info(info);
    preserve_boot_info(info);
    runtime_self_test();

    gdt_init();
    interrupts_init();
    pmm_init(&boot_info_copy, e820_copy);
    vmm_init(&boot_info_copy);
    heap_init();
    memory_self_test();
    pic_init();
    console_write("K3:PIC OK vectors=32..47\n");
    pit_init();
    console_printf("K3:PIT OK hz=%u\n", (unsigned int)PIT_TICKS_PER_SECOND);
    keyboard_init();
    console_write("K3:KEYBOARD READY\n");

#if KERNEL_TEST_MODE == KERNEL_TEST_DIVIDE_ERROR
    trigger_divide_error();
#elif KERNEL_TEST_MODE == KERNEL_TEST_UNMAPPED_PAGE
    trigger_unmapped_page();
#elif KERNEL_TEST_MODE == KERNEL_TEST_READ_ONLY_PAGE
    trigger_read_only_page();
#elif KERNEL_TEST_MODE == KERNEL_TEST_NX_PAGE
    trigger_nx_page();
#elif KERNEL_TEST_MODE == KERNEL_TEST_NORMAL
    run_normal_interrupt_test();
#else
#error "unsupported KERNEL_TEST_MODE"
#endif
}
