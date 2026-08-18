#include <kernel/boot_info.h>
#include <kernel/types.h>

#define COM1_BASE 0x3f8U

__attribute__((section(".rodata.kernel_identity"), used))
const char kernel_identity[] = "tiny-linux-kernel M2";

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

static void serial_write(const char *text)
{
    while (*text != '\0') {
        serial_putc(*text++);
    }
}

static void serial_write_hex(u64 value)
{
    static const char digits[] = "0123456789abcdef";
    u32 shift;

    serial_write("0x");
    for (shift = 60U;; shift -= 4U) {
        serial_putc(digits[(value >> shift) & 0x0fU]);
        if (shift == 0U) {
            break;
        }
    }
}

static __attribute__((noreturn)) void halt_forever(void)
{
    for (;;) {
        __asm__ volatile("hlt");
    }
}

__attribute__((noreturn))
void kernel_main(const struct boot_info *info)
{
    const struct e820_entry *entries;
    u32 index;

    serial_init();
    serial_write("K2:LONG MODE OK\r\n");

    if (info == (const struct boot_info *)0 ||
        info->version != BOOT_INFO_VERSION ||
        info->size != sizeof(struct boot_info) ||
        info->e820_count == 0U ||
        info->e820_count > BOOT_INFO_MAX_E820_ENTRIES) {
        serial_write("K2:BOOT INFO ERROR\r\n");
        halt_forever();
    }

    serial_write("K2:BOOT drive=");
    serial_write_hex(info->boot_drive);
    serial_write(" entries=");
    serial_write_hex(info->e820_count);
    serial_write("\r\n");

    serial_write("K2:KERNEL phys=");
    serial_write_hex(info->kernel_phys_start);
    serial_write("..");
    serial_write_hex(info->kernel_phys_end);
    serial_write(" virt=");
    serial_write_hex(info->kernel_virt_start);
    serial_write("..");
    serial_write_hex(info->kernel_virt_end);
    serial_write(" entry=");
    serial_write_hex(info->kernel_entry);
    serial_write("\r\n");

    entries = (const struct e820_entry *)(uptr)info->e820_entries;
    for (index = 0U; index < info->e820_count; ++index) {
        serial_write("K2:E820[");
        serial_write_hex(index);
        serial_write("] base=");
        serial_write_hex(entries[index].base);
        serial_write(" length=");
        serial_write_hex(entries[index].length);
        serial_write(" type=");
        serial_write_hex(entries[index].type);
        serial_write(" attr=");
        serial_write_hex(entries[index].attributes);
        serial_write("\r\n");
    }

    serial_write("K2:HALT\r\n");
    halt_forever();
}
