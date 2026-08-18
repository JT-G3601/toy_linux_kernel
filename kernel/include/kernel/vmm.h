#ifndef TINY_LINUX_KERNEL_VMM_H
#define TINY_LINUX_KERNEL_VMM_H

#include <kernel/boot_info.h>
#include <kernel/types.h>

#define VM_WRITE (1ULL << 0U)
#define VM_USER (1ULL << 1U)
#define VM_EXEC (1ULL << 2U)

void vmm_init(const struct boot_info *info);
bool vm_map(u64 virtual_address, u64 physical_address, u64 flags);
bool vm_unmap(u64 virtual_address, u64 *physical_address);
bool vm_protect(u64 virtual_address, u64 flags);
bool vm_translate(u64 virtual_address, u64 *physical_address, u64 *flags);
u64 vmm_root_physical(void);

#endif
