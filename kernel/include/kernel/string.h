#ifndef TINY_LINUX_KERNEL_STRING_H
#define TINY_LINUX_KERNEL_STRING_H

#include <kernel/types.h>

void *memcpy(void *destination, const void *source, usize count);
void *memset(void *destination, int value, usize count);
void *memmove(void *destination, const void *source, usize count);
usize strlen(const char *text);

#endif
