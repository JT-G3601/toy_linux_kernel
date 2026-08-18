#ifndef TINY_LINUX_KERNEL_PIC_H
#define TINY_LINUX_KERNEL_PIC_H

#include <kernel/types.h>

void pic_init(void);
void pic_unmask_irq(u8 irq);
void pic_send_eoi(u8 irq);

#endif
