#ifndef TINY_LINUX_KERNEL_IO_H
#define TINY_LINUX_KERNEL_IO_H

#include <kernel/types.h>

static inline void outb(u16 port, u8 value)
{
    __asm__ volatile("outb %0, %1" : : "a"(value), "Nd"(port));
}

static inline u8 inb(u16 port)
{
    u8 value;

    __asm__ volatile("inb %1, %0" : "=a"(value) : "Nd"(port));
    return value;
}

static inline void io_wait(void)
{
    outb(0x80U, 0U);
}

static inline void interrupts_enable(void)
{
    __asm__ volatile("sti" : : : "memory");
}

static inline void interrupts_disable(void)
{
    __asm__ volatile("cli" : : : "memory");
}

static inline void cpu_halt(void)
{
    __asm__ volatile("hlt");
}

#endif
