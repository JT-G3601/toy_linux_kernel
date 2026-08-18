#ifndef TINY_LINUX_KERNEL_KEYBOARD_H
#define TINY_LINUX_KERNEL_KEYBOARD_H

#include <kernel/types.h>

void keyboard_init(void);
void keyboard_on_irq(void);
u64 keyboard_event_count(void);
char keyboard_last_char(void);

#endif
