#include <kernel/console.h>
#include <kernel/heap.h>
#include <kernel/memory_layout.h>
#include <kernel/pmm.h>
#include <kernel/vmm.h>

#define HEAP_ALIGNMENT 16ULL
#define HEAP_FREE_FLAG 1ULL
#define HEAP_FLAG_MASK 0xfULL
#define HEAP_MIN_PAYLOAD 16ULL

struct heap_block {
    u64 size_and_flags;
    struct heap_block *previous_free;
    struct heap_block *next_free;
};

#define HEAP_OVERHEAD (sizeof(struct heap_block) + sizeof(u64))
#define HEAP_MIN_BLOCK_SIZE (HEAP_OVERHEAD + HEAP_MIN_PAYLOAD)

static struct heap_block *free_list;
static u64 mapped_end;
static struct heap_stats statistics;
static bool initialized;

static u64 block_size(const struct heap_block *block)
{
    return block->size_and_flags & ~HEAP_FLAG_MASK;
}

static bool block_is_free(const struct heap_block *block)
{
    return (block->size_and_flags & HEAP_FREE_FLAG) != 0ULL;
}

static u64 *block_footer(struct heap_block *block)
{
    return (u64 *)((u8 *)block + block_size(block) - sizeof(u64));
}

static void write_block(struct heap_block *block, u64 size, bool free)
{
    block->size_and_flags = size | (free ? HEAP_FREE_FLAG : 0ULL);
    *block_footer(block) = block->size_and_flags;
}

static void free_list_remove(struct heap_block *block)
{
    if (block->previous_free != (struct heap_block *)0) {
        block->previous_free->next_free = block->next_free;
    } else {
        free_list = block->next_free;
    }
    if (block->next_free != (struct heap_block *)0) {
        block->next_free->previous_free = block->previous_free;
    }
    block->previous_free = (struct heap_block *)0;
    block->next_free = (struct heap_block *)0;
}

static void free_list_insert(struct heap_block *block)
{
    block->previous_free = (struct heap_block *)0;
    block->next_free = free_list;
    if (free_list != (struct heap_block *)0) {
        free_list->previous_free = block;
    }
    free_list = block;
}

static void validate_block(const struct heap_block *block)
{
    const u64 address = (u64)(uptr)block;
    const u64 size = block_size(block);

    if (address < KERNEL_HEAP_BASE || address >= mapped_end ||
        size < HEAP_MIN_BLOCK_SIZE || (size & (HEAP_ALIGNMENT - 1ULL)) != 0ULL ||
        address + size > mapped_end ||
        *(const u64 *)(uptr)(address + size - sizeof(u64)) != block->size_and_flags) {
        panic("heap boundary tag corruption at 0x%llx", address);
    }
}

static void heap_expand(u64 minimum_bytes)
{
    u64 bytes = align_up_u64(minimum_bytes, PAGE_SIZE);
    u64 old_end = mapped_end;
    u64 new_end = old_end + bytes;
    u64 virtual_address;
    struct heap_block *block;

    if (new_end < old_end || new_end > KERNEL_HEAP_LIMIT) {
        panic("kernel heap exhausted");
    }
    for (virtual_address = old_end; virtual_address < new_end;
         virtual_address += PAGE_SIZE) {
        u64 physical_address = page_alloc();

        if (!vm_map(virtual_address, physical_address, VM_WRITE)) {
            panic("failed to map heap page at 0x%llx", virtual_address);
        }
        ++statistics.mapped_pages;
    }
    mapped_end = new_end;
    block = (struct heap_block *)(uptr)old_end;
    write_block(block, bytes, true);

    if (old_end != KERNEL_HEAP_BASE) {
        u64 previous_tag = *(const u64 *)(uptr)(old_end - sizeof(u64));
        u64 previous_size = previous_tag & ~HEAP_FLAG_MASK;

        if ((previous_tag & HEAP_FREE_FLAG) != 0ULL) {
            struct heap_block *previous =
                (struct heap_block *)(uptr)(old_end - previous_size);

            validate_block(previous);
            free_list_remove(previous);
            write_block(previous, previous_size + bytes, true);
            block = previous;
        }
    }
    free_list_insert(block);
}

void heap_init(void)
{
    if (initialized) {
        panic("heap initialized twice");
    }
    free_list = (struct heap_block *)0;
    mapped_end = KERNEL_HEAP_BASE;
    statistics.mapped_pages = 0ULL;
    statistics.allocated_blocks = 0ULL;
    statistics.allocated_bytes = 0ULL;
    statistics.free_bytes = 0ULL;
    initialized = true;
    heap_expand(PAGE_SIZE);
    console_printf("K4:HEAP READY base=0x%llx limit=0x%llx\n",
                   KERNEL_HEAP_BASE, KERNEL_HEAP_LIMIT);
}

void *kmalloc(usize size)
{
    struct heap_block *block;
    u64 required;

    if (!initialized) {
        panic("kmalloc before heap_init");
    }
    if (size == 0U) {
        return (void *)0;
    }
    if ((u64)size > KERNEL_HEAP_LIMIT - KERNEL_HEAP_BASE - HEAP_OVERHEAD) {
        panic("kmalloc request too large: %llu", (u64)size);
    }
    required = align_up_u64((u64)size + HEAP_OVERHEAD, HEAP_ALIGNMENT);
    if (required < HEAP_MIN_BLOCK_SIZE) {
        required = HEAP_MIN_BLOCK_SIZE;
    }

    for (;;) {
        for (block = free_list; block != (struct heap_block *)0;
             block = block->next_free) {
            validate_block(block);
            if (block_size(block) >= required) {
                u64 original_size = block_size(block);

                free_list_remove(block);
                if (original_size - required >= HEAP_MIN_BLOCK_SIZE) {
                    struct heap_block *remainder =
                        (struct heap_block *)((u8 *)block + required);

                    write_block(block, required, false);
                    write_block(remainder, original_size - required, true);
                    free_list_insert(remainder);
                } else {
                    write_block(block, original_size, false);
                }
                ++statistics.allocated_blocks;
                statistics.allocated_bytes += block_size(block) - HEAP_OVERHEAD;
                return (u8 *)block + sizeof(struct heap_block);
            }
        }
        heap_expand(required);
    }
}

void kfree(void *pointer)
{
    struct heap_block *block;
    u64 size;

    if (pointer == (void *)0) {
        return;
    }
    if (!initialized || (u64)(uptr)pointer < KERNEL_HEAP_BASE + sizeof(*block) ||
        (u64)(uptr)pointer >= mapped_end ||
        ((u64)(uptr)pointer & (HEAP_ALIGNMENT - 1ULL)) != 8ULL) {
        panic("kfree invalid pointer: %p", pointer);
    }
    block = (struct heap_block *)((u8 *)pointer - sizeof(struct heap_block));
    validate_block(block);
    if (block_is_free(block)) {
        panic("duplicate kfree: %p", pointer);
    }
    size = block_size(block);
    --statistics.allocated_blocks;
    statistics.allocated_bytes -= size - HEAP_OVERHEAD;
    write_block(block, size, true);

    if ((u64)(uptr)block + size < mapped_end) {
        struct heap_block *next = (struct heap_block *)((u8 *)block + size);

        validate_block(next);
        if (block_is_free(next)) {
            free_list_remove(next);
            size += block_size(next);
            write_block(block, size, true);
        }
    }
    if ((u64)(uptr)block > KERNEL_HEAP_BASE) {
        u64 previous_tag = *(const u64 *)((const u8 *)block - sizeof(u64));

        if ((previous_tag & HEAP_FREE_FLAG) != 0ULL) {
            u64 previous_size = previous_tag & ~HEAP_FLAG_MASK;
            struct heap_block *previous =
                (struct heap_block *)((u8 *)block - previous_size);

            validate_block(previous);
            free_list_remove(previous);
            size += previous_size;
            block = previous;
            write_block(block, size, true);
        }
    }
    free_list_insert(block);
}

struct heap_stats heap_get_stats(void)
{
    struct heap_stats result = statistics;
    u64 address = KERNEL_HEAP_BASE;

    result.free_bytes = 0ULL;
    while (address < mapped_end) {
        struct heap_block *block = (struct heap_block *)(uptr)address;

        validate_block(block);
        if (block_is_free(block)) {
            result.free_bytes += block_size(block) - HEAP_OVERHEAD;
        }
        address += block_size(block);
    }
    return result;
}
