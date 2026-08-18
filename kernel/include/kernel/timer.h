#ifndef TINY_LINUX_KERNEL_TIMER_H
#define TINY_LINUX_KERNEL_TIMER_H

#include <kernel/types.h>

#define PIT_TICKS_PER_SECOND 100U

void pit_init(void);
void pit_on_irq(void);
u64 pit_ticks(void);

#endif
