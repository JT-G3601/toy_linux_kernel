#include <stdarg.h>

#include <kernel/console.h>
#include <kernel/io.h>

#define COM1_BASE 0x3f8U
#define VGA_WIDTH 80U
#define VGA_HEIGHT 25U
#define VGA_ATTRIBUTE 0x07U

static volatile u16 *const vga_buffer = (volatile u16 *)(uptr)0xb8000U;
static usize vga_row;
static usize vga_column;

static void serial_init(void)
{
    outb(COM1_BASE + 1U, 0x00U);
    outb(COM1_BASE + 3U, 0x80U);
    outb(COM1_BASE, 0x01U);
    outb(COM1_BASE + 1U, 0x00U);
    outb(COM1_BASE + 3U, 0x03U);
    outb(COM1_BASE + 2U, 0xc7U);
    outb(COM1_BASE + 4U, 0x0bU);
}

static void serial_putc(char value)
{
    while ((inb(COM1_BASE + 5U) & 0x20U) == 0U) {
    }
    outb(COM1_BASE, (u8)value);
}

static void vga_scroll(void)
{
    usize row;
    usize column;
    const u16 blank = ((u16)VGA_ATTRIBUTE << 8U) | (u16)' ';

    if (vga_row < VGA_HEIGHT) {
        return;
    }
    for (row = 1U; row < VGA_HEIGHT; ++row) {
        for (column = 0U; column < VGA_WIDTH; ++column) {
            vga_buffer[(row - 1U) * VGA_WIDTH + column] =
                vga_buffer[row * VGA_WIDTH + column];
        }
    }
    for (column = 0U; column < VGA_WIDTH; ++column) {
        vga_buffer[(VGA_HEIGHT - 1U) * VGA_WIDTH + column] = blank;
    }
    vga_row = VGA_HEIGHT - 1U;
}

static void vga_putc(char value)
{
    if (value == '\n') {
        vga_column = 0U;
        ++vga_row;
        vga_scroll();
        return;
    }
    if (value == '\r') {
        vga_column = 0U;
        return;
    }
    if (value == '\b') {
        if (vga_column != 0U) {
            --vga_column;
            vga_buffer[vga_row * VGA_WIDTH + vga_column] =
                ((u16)VGA_ATTRIBUTE << 8U) | (u16)' ';
        }
        return;
    }

    vga_buffer[vga_row * VGA_WIDTH + vga_column] =
        ((u16)VGA_ATTRIBUTE << 8U) | (u8)value;
    ++vga_column;
    if (vga_column == VGA_WIDTH) {
        vga_column = 0U;
        ++vga_row;
        vga_scroll();
    }
}

void console_init(void)
{
    usize index;
    const u16 blank = ((u16)VGA_ATTRIBUTE << 8U) | (u16)' ';

    serial_init();
    vga_row = 0U;
    vga_column = 0U;
    for (index = 0U; index < VGA_WIDTH * VGA_HEIGHT; ++index) {
        vga_buffer[index] = blank;
    }
}

void console_putc(char value)
{
    vga_putc(value);
    if (value == '\n') {
        serial_putc('\r');
    }
    serial_putc(value);
}

void console_write(const char *text)
{
    while (*text != '\0') {
        console_putc(*text++);
    }
}

static void console_write_unsigned(u64 value, u32 base, bool prefix)
{
    static const char digits[] = "0123456789abcdef";
    char buffer[32];
    usize length = 0U;

    if (prefix && base == 16U) {
        console_write("0x");
    }
    do {
        buffer[length++] = digits[value % base];
        value /= base;
    } while (value != 0U);
    while (length != 0U) {
        console_putc(buffer[--length]);
    }
}

static void console_vprintf(const char *format, va_list arguments)
{
    while (*format != '\0') {
        bool long_long = false;

        if (*format != '%') {
            console_putc(*format++);
            continue;
        }
        ++format;
        if (*format == 'l') {
            ++format;
            if (*format == 'l') {
                long_long = true;
                ++format;
            }
        }
        switch (*format) {
        case '%':
            console_putc('%');
            break;
        case 'c':
            console_putc((char)va_arg(arguments, int));
            break;
        case 's': {
            const char *text = va_arg(arguments, const char *);
            console_write(text == (const char *)0 ? "(null)" : text);
            break;
        }
        case 'd': {
            i64 value = long_long ? va_arg(arguments, i64) : va_arg(arguments, int);
            if (value < 0) {
                console_putc('-');
                console_write_unsigned((u64)(-(value + 1)) + 1U, 10U, false);
            } else {
                console_write_unsigned((u64)value, 10U, false);
            }
            break;
        }
        case 'u': {
            u64 value = long_long ? va_arg(arguments, u64) : va_arg(arguments, unsigned int);
            console_write_unsigned(value, 10U, false);
            break;
        }
        case 'x': {
            u64 value = long_long ? va_arg(arguments, u64) : va_arg(arguments, unsigned int);
            console_write_unsigned(value, 16U, false);
            break;
        }
        case 'p':
            console_write_unsigned((u64)(uptr)va_arg(arguments, void *), 16U, true);
            break;
        case '\0':
            return;
        default:
            console_putc('%');
            console_putc(*format);
            break;
        }
        ++format;
    }
}

void console_printf(const char *format, ...)
{
    va_list arguments;

    va_start(arguments, format);
    console_vprintf(format, arguments);
    va_end(arguments);
}

__attribute__((noreturn))
void panic(const char *format, ...)
{
    va_list arguments;

    interrupts_disable();
    console_write("PANIC: ");
    va_start(arguments, format);
    console_vprintf(format, arguments);
    va_end(arguments);
    console_putc('\n');
    for (;;) {
        cpu_halt();
    }
}
