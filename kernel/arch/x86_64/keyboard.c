#include <kernel/console.h>
#include <kernel/io.h>
#include <kernel/keyboard.h>
#include <kernel/pic.h>

#define PS2_DATA_PORT 0x60U

static const char normal_map[128] = {
    [0x02] = '1', [0x03] = '2', [0x04] = '3', [0x05] = '4',
    [0x06] = '5', [0x07] = '6', [0x08] = '7', [0x09] = '8',
    [0x0a] = '9', [0x0b] = '0', [0x0c] = '-', [0x0d] = '=',
    [0x0e] = '\b', [0x0f] = '\t', [0x10] = 'q', [0x11] = 'w',
    [0x12] = 'e', [0x13] = 'r', [0x14] = 't', [0x15] = 'y',
    [0x16] = 'u', [0x17] = 'i', [0x18] = 'o', [0x19] = 'p',
    [0x1a] = '[', [0x1b] = ']', [0x1c] = '\n', [0x1e] = 'a',
    [0x1f] = 's', [0x20] = 'd', [0x21] = 'f', [0x22] = 'g',
    [0x23] = 'h', [0x24] = 'j', [0x25] = 'k', [0x26] = 'l',
    [0x27] = ';', [0x28] = '\'', [0x29] = '`', [0x2b] = '\\',
    [0x2c] = 'z', [0x2d] = 'x', [0x2e] = 'c', [0x2f] = 'v',
    [0x30] = 'b', [0x31] = 'n', [0x32] = 'm', [0x33] = ',',
    [0x34] = '.', [0x35] = '/', [0x39] = ' '
};

static const char shift_map[128] = {
    [0x02] = '!', [0x03] = '@', [0x04] = '#', [0x05] = '$',
    [0x06] = '%', [0x07] = '^', [0x08] = '&', [0x09] = '*',
    [0x0a] = '(', [0x0b] = ')', [0x0c] = '_', [0x0d] = '+',
    [0x0e] = '\b', [0x0f] = '\t', [0x10] = 'Q', [0x11] = 'W',
    [0x12] = 'E', [0x13] = 'R', [0x14] = 'T', [0x15] = 'Y',
    [0x16] = 'U', [0x17] = 'I', [0x18] = 'O', [0x19] = 'P',
    [0x1a] = '{', [0x1b] = '}', [0x1c] = '\n', [0x1e] = 'A',
    [0x1f] = 'S', [0x20] = 'D', [0x21] = 'F', [0x22] = 'G',
    [0x23] = 'H', [0x24] = 'J', [0x25] = 'K', [0x26] = 'L',
    [0x27] = ':', [0x28] = '"', [0x29] = '~', [0x2b] = '|',
    [0x2c] = 'Z', [0x2d] = 'X', [0x2e] = 'C', [0x2f] = 'V',
    [0x30] = 'B', [0x31] = 'N', [0x32] = 'M', [0x33] = '<',
    [0x34] = '>', [0x35] = '?', [0x39] = ' '
};

static bool shift_pressed;
static volatile u64 event_count;
static volatile char last_character;

void keyboard_init(void)
{
    shift_pressed = false;
    event_count = 0U;
    last_character = '\0';
    pic_unmask_irq(1U);
}

void keyboard_on_irq(void)
{
    const u8 scan_code = inb(PS2_DATA_PORT);
    char character;

    if (scan_code == 0x2aU || scan_code == 0x36U) {
        shift_pressed = true;
        return;
    }
    if (scan_code == 0xaaU || scan_code == 0xb6U) {
        shift_pressed = false;
        return;
    }
    if ((scan_code & 0x80U) != 0U || scan_code >= 128U) {
        return;
    }

    character = shift_pressed ? shift_map[scan_code] : normal_map[scan_code];
    if (character == '\0') {
        return;
    }
    last_character = character;
    ++event_count;
    console_printf("K3:KEY char=%c scan=0x%x\n", character, (unsigned int)scan_code);
}

u64 keyboard_event_count(void)
{
    return event_count;
}

char keyboard_last_char(void)
{
    return last_character;
}
