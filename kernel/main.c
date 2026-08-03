#include <kernel/types.h>

__attribute__((section(".rodata.kernel_identity"), used))
const char kernel_identity[] = "tiny-linux-kernel M0";

/*
 * M0 only proves that a freestanding higher-half ELF can be compiled and
 * linked. Stage2 will call this entry after it establishes long mode and the
 * required mappings in M2.
 */
__attribute__((noreturn))
void kernel_main(void)
{
    for (;;) {
        __asm__ volatile("hlt");
    }
}
