#include <kernel/console.h>
#include <kernel/memory_layout.h>
#include <kernel/pmm.h>
#include <kernel/string.h>

#define PMM_FRAME_COUNT (PMM_PHYSICAL_LIMIT / PAGE_SIZE)
#define PMM_BITMAP_WORDS (PMM_FRAME_COUNT / 64ULL)
#define E820_TYPE_USABLE 1U
#define LOW_MEMORY_RESERVED_END 0x00100000ULL

static u64 allocated_bitmap[PMM_BITMAP_WORDS];
static u64 managed_bitmap[PMM_BITMAP_WORDS];
static u64 allocator_owned_bitmap[PMM_BITMAP_WORDS];
static struct pmm_stats statistics;
static bool initialized;

static bool bitmap_test(const u64 *bitmap, u64 frame)
{
    return (bitmap[frame / 64ULL] & (1ULL << (frame % 64ULL))) != 0ULL;
}

static void bitmap_set(u64 *bitmap, u64 frame)
{
    bitmap[frame / 64ULL] |= 1ULL << (frame % 64ULL);
}

static void bitmap_clear(u64 *bitmap, u64 frame)
{
    bitmap[frame / 64ULL] &= ~(1ULL << (frame % 64ULL));
}

static void mark_usable_range(u64 base, u64 length)
{
    u64 end;
    u64 first_frame;
    u64 end_frame;
    u64 frame;

    if (length == 0ULL || base >= PMM_PHYSICAL_LIMIT) {
        return;
    }
    end = base + length;
    if (end < base || end > PMM_PHYSICAL_LIMIT) {
        end = PMM_PHYSICAL_LIMIT;
    }
    base = align_up_u64(base, PAGE_SIZE);
    end = align_down_u64(end, PAGE_SIZE);
    if (base >= end) {
        return;
    }

    first_frame = base / PAGE_SIZE;
    end_frame = end / PAGE_SIZE;
    for (frame = first_frame; frame < end_frame; ++frame) {
        if (!bitmap_test(managed_bitmap, frame)) {
            bitmap_set(managed_bitmap, frame);
            bitmap_clear(allocated_bitmap, frame);
            ++statistics.managed_pages;
            ++statistics.free_pages;
        }
    }
}

static void reserve_range(u64 base, u64 end)
{
    u64 frame;
    u64 end_frame;

    base = align_down_u64(base, PAGE_SIZE);
    end = align_up_u64(end, PAGE_SIZE);
    if (base >= PMM_PHYSICAL_LIMIT) {
        return;
    }
    if (end > PMM_PHYSICAL_LIMIT || end < base) {
        end = PMM_PHYSICAL_LIMIT;
    }
    end_frame = end / PAGE_SIZE;
    for (frame = base / PAGE_SIZE; frame < end_frame; ++frame) {
        if (bitmap_test(managed_bitmap, frame) &&
            !bitmap_test(allocated_bitmap, frame)) {
            bitmap_set(allocated_bitmap, frame);
            --statistics.free_pages;
        }
    }
}

void pmm_init(const struct boot_info *info, const struct e820_entry *entries)
{
    u32 index;

    if (initialized) {
        panic("PMM initialized twice");
    }
    memset(allocated_bitmap, 0xff, sizeof(allocated_bitmap));
    memset(managed_bitmap, 0, sizeof(managed_bitmap));
    memset(allocator_owned_bitmap, 0, sizeof(allocator_owned_bitmap));
    memset(&statistics, 0, sizeof(statistics));
    statistics.physical_limit = PMM_PHYSICAL_LIMIT;

    for (index = 0U; index < info->e820_count; ++index) {
        if (entries[index].type == E820_TYPE_USABLE) {
            mark_usable_range(entries[index].base, entries[index].length);
        }
    }

    /* Covers IVT/BDA, boot stages, boot_info/E820, M2 tables/stacks, and VGA. */
    reserve_range(0ULL, LOW_MEMORY_RESERVED_END);
    reserve_range(info->kernel_phys_start, info->kernel_phys_end);
    statistics.allocated_pages = statistics.managed_pages - statistics.free_pages;
    initialized = true;

    if (statistics.free_pages == 0ULL) {
        panic("PMM found no usable pages below 1 GiB");
    }
    console_printf("K4:PMM READY managed=%llu free=%llu limit=0x%llx\n",
                   statistics.managed_pages, statistics.free_pages,
                   statistics.physical_limit);
}

u64 page_alloc(void)
{
    u64 word;

    if (!initialized) {
        panic("page_alloc before pmm_init");
    }
    for (word = 0ULL; word < PMM_BITMAP_WORDS; ++word) {
        u64 available = managed_bitmap[word] & ~allocated_bitmap[word];

        if (available != 0ULL) {
            u32 bit = (u32)__builtin_ctzll(available);
            u64 frame = word * 64ULL + bit;

            bitmap_set(allocated_bitmap, frame);
            bitmap_set(allocator_owned_bitmap, frame);
            --statistics.free_pages;
            ++statistics.allocated_pages;
            return frame * PAGE_SIZE;
        }
    }
    panic("physical page allocator exhausted");
}

void page_free(u64 physical_address)
{
    u64 frame;

    if (!initialized) {
        panic("page_free before pmm_init");
    }
    if ((physical_address & PAGE_MASK) != 0ULL ||
        physical_address >= PMM_PHYSICAL_LIMIT) {
        panic("page_free out of range: 0x%llx", physical_address);
    }
    frame = physical_address / PAGE_SIZE;
    if (!bitmap_test(managed_bitmap, frame)) {
        panic("page_free unmanaged frame: 0x%llx", physical_address);
    }
    if (!bitmap_test(allocator_owned_bitmap, frame)) {
        if (!bitmap_test(allocated_bitmap, frame)) {
            panic("duplicate page_free: 0x%llx", physical_address);
        }
        panic("page_free reserved frame: 0x%llx", physical_address);
    }
    if (!bitmap_test(allocated_bitmap, frame)) {
        panic("duplicate page_free: 0x%llx", physical_address);
    }
    bitmap_clear(allocator_owned_bitmap, frame);
    bitmap_clear(allocated_bitmap, frame);
    ++statistics.free_pages;
    --statistics.allocated_pages;
}

bool pmm_page_is_managed(u64 physical_address)
{
    if ((physical_address & PAGE_MASK) != 0ULL ||
        physical_address >= PMM_PHYSICAL_LIMIT) {
        return false;
    }
    return bitmap_test(managed_bitmap, physical_address / PAGE_SIZE);
}

bool pmm_page_is_allocated(u64 physical_address)
{
    if (!pmm_page_is_managed(physical_address)) {
        return false;
    }
    return bitmap_test(allocated_bitmap, physical_address / PAGE_SIZE);
}

struct pmm_stats pmm_get_stats(void)
{
    return statistics;
}
