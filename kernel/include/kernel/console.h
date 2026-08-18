#ifndef TINY_LINUX_KERNEL_CONSOLE_H
#define TINY_LINUX_KERNEL_CONSOLE_H

#include <kernel/types.h>

void console_init(void);
void console_putc(char value);
void console_write(const char *text);
void console_printf(const char *format, ...);

__attribute__((noreturn))
void panic(const char *format, ...);

#endif
