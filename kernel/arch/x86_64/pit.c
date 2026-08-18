#include <kernel/io.h>
#include <kernel/pic.h>
#include <kernel/timer.h>

#define PIT_INPUT_FREQUENCY 1193182U
#define PIT_CHANNEL0 0x40U
#define PIT_COMMAND 0x43U

static volatile u64 tick_count;

void pit_init(void)
{
    const u16 divisor = (u16)(PIT_INPUT_FREQUENCY / PIT_TICKS_PER_SECOND);

    tick_count = 0U;
    outb(PIT_COMMAND, 0x36U);
    outb(PIT_CHANNEL0, (u8)divisor);
    outb(PIT_CHANNEL0, (u8)(divisor >> 8U));
    pic_unmask_irq(0U);
}

void pit_on_irq(void)
{
    ++tick_count;
}

u64 pit_ticks(void)
{
    return tick_count;
}
