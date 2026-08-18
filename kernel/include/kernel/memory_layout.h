#ifndef TINY_LINUX_KERNEL_MEMORY_LAYOUT_H
#define TINY_LINUX_KERNEL_MEMORY_LAYOUT_H

#include <kernel/types.h>

#define PAGE_SIZE 4096ULL
#define PAGE_MASK (PAGE_SIZE - 1ULL)

/* M4 deliberately manages and direct-maps at most the first GiB. */
#define PMM_PHYSICAL_LIMIT 0x40000000ULL
#define PHYSICAL_DIRECT_MAP_BASE 0xffff800000000000ULL

#define KERNEL_HEAP_BASE 0xffffc10000000000ULL
#define KERNEL_HEAP_LIMIT (KERNEL_HEAP_BASE + 0x01000000ULL)

#define KERNEL_VM_TEST_BASE 0xffffc00000000000ULL

static inline u64 align_down_u64(u64 value, u64 alignment)
{
    return value & ~(alignment - 1ULL);
}

static inline u64 align_up_u64(u64 value, u64 alignment)
{
    return (value + alignment - 1ULL) & ~(alignment - 1ULL);
}

static inline void *physical_to_virtual(u64 physical_address)
{
    return (void *)(uptr)(PHYSICAL_DIRECT_MAP_BASE + physical_address);
}

#endif
