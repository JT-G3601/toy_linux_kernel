#ifndef TINY_LINUX_KERNEL_PMM_H
#define TINY_LINUX_KERNEL_PMM_H

#include <kernel/boot_info.h>
#include <kernel/types.h>

struct pmm_stats {
    u64 managed_pages;
    u64 free_pages;
    u64 allocated_pages;
    u64 physical_limit;
};

void pmm_init(const struct boot_info *info, const struct e820_entry *entries);
u64 page_alloc(void);
void page_free(u64 physical_address);
bool pmm_page_is_managed(u64 physical_address);
bool pmm_page_is_allocated(u64 physical_address);
struct pmm_stats pmm_get_stats(void);

#endif
