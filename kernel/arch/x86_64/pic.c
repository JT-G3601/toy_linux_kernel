#include <kernel/io.h>
#include <kernel/pic.h>

#define PIC_MASTER_COMMAND 0x20U
#define PIC_MASTER_DATA 0x21U
#define PIC_SLAVE_COMMAND 0xa0U
#define PIC_SLAVE_DATA 0xa1U
#define PIC_EOI 0x20U

void pic_init(void)
{
    outb(PIC_MASTER_COMMAND, 0x11U);
    io_wait();
    outb(PIC_SLAVE_COMMAND, 0x11U);
    io_wait();
    outb(PIC_MASTER_DATA, 0x20U);
    io_wait();
    outb(PIC_SLAVE_DATA, 0x28U);
    io_wait();
    outb(PIC_MASTER_DATA, 0x04U);
    io_wait();
    outb(PIC_SLAVE_DATA, 0x02U);
    io_wait();
    outb(PIC_MASTER_DATA, 0x01U);
    io_wait();
    outb(PIC_SLAVE_DATA, 0x01U);
    io_wait();
    outb(PIC_MASTER_DATA, 0xffU);
    outb(PIC_SLAVE_DATA, 0xffU);
}

void pic_unmask_irq(u8 irq)
{
    const u16 port = irq < 8U ? PIC_MASTER_DATA : PIC_SLAVE_DATA;
    const u8 bit = irq < 8U ? irq : (u8)(irq - 8U);
    const u8 mask = inb(port);

    outb(port, (u8)(mask & (u8)~(1U << bit)));
    if (irq >= 8U) {
        outb(PIC_MASTER_DATA, (u8)(inb(PIC_MASTER_DATA) & (u8)~(1U << 2U)));
    }
}

void pic_send_eoi(u8 irq)
{
    if (irq >= 8U) {
        outb(PIC_SLAVE_COMMAND, PIC_EOI);
    }
    outb(PIC_MASTER_COMMAND, PIC_EOI);
}
