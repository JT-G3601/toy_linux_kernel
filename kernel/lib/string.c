#include <kernel/string.h>

void *memcpy(void *destination, const void *source, usize count)
{
    u8 *destination_bytes = (u8 *)destination;
    const u8 *source_bytes = (const u8 *)source;
    usize index;

    for (index = 0U; index < count; ++index) {
        destination_bytes[index] = source_bytes[index];
    }
    return destination;
}

void *memset(void *destination, int value, usize count)
{
    u8 *bytes = (u8 *)destination;
    usize index;

    for (index = 0U; index < count; ++index) {
        bytes[index] = (u8)value;
    }
    return destination;
}

void *memmove(void *destination, const void *source, usize count)
{
    u8 *destination_bytes = (u8 *)destination;
    const u8 *source_bytes = (const u8 *)source;
    usize index;

    if (destination_bytes == source_bytes || count == 0U) {
        return destination;
    }
    if (destination_bytes < source_bytes) {
        for (index = 0U; index < count; ++index) {
            destination_bytes[index] = source_bytes[index];
        }
    } else {
        for (index = count; index != 0U; --index) {
            destination_bytes[index - 1U] = source_bytes[index - 1U];
        }
    }
    return destination;
}

usize strlen(const char *text)
{
    usize length = 0U;

    while (text[length] != '\0') {
        ++length;
    }
    return length;
}
