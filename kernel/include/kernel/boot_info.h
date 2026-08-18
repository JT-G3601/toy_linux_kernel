#ifndef TINY_LINUX_KERNEL_BOOT_INFO_H
#define TINY_LINUX_KERNEL_BOOT_INFO_H

#include <kernel/types.h>

#define BOOT_INFO_VERSION 1U
#define BOOT_INFO_MAX_E820_ENTRIES 64U

struct e820_entry {
    u64 base;
    u64 length;
    u32 type;
    u32 attributes;
} __attribute__((packed));

struct boot_info {
    u32 version;
    u32 size;
    u32 boot_drive;
    u32 e820_count;
    u64 e820_entries;
    u64 kernel_phys_start;
    u64 kernel_phys_end;
    u64 kernel_virt_start;
    u64 kernel_virt_end;
    u64 kernel_entry;
} __attribute__((packed));

_Static_assert(sizeof(struct e820_entry) == 24, "E820 entry ABI must be 24 bytes");
_Static_assert(sizeof(struct boot_info) == 64, "boot_info v1 ABI must be 64 bytes");

#endif
