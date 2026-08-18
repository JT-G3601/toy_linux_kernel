#ifndef TINY_LINUX_KERNEL_HEAP_H
#define TINY_LINUX_KERNEL_HEAP_H

#include <kernel/types.h>

struct heap_stats {
    u64 mapped_pages;
    u64 allocated_blocks;
    u64 allocated_bytes;
    u64 free_bytes;
};

void heap_init(void);
void *kmalloc(usize size);
void kfree(void *pointer);
struct heap_stats heap_get_stats(void);

#endif
