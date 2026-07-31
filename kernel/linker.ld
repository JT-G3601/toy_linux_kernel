OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)
ENTRY(_start)

KERNEL_VMA = 0xffffffff80000000;
KERNEL_LMA = 0x00100000;
PAGE_SIZE = 0x1000;

PHDRS
{
    text   PT_LOAD FLAGS(5);
    rodata PT_LOAD FLAGS(4);
    data   PT_LOAD FLAGS(6);
}

SECTIONS
{
    . = KERNEL_VMA;
    __kernel_virtual_start = .;
    __kernel_physical_start = KERNEL_LMA;

    .text : AT(KERNEL_LMA)
    {
        KEEP(*(.text.boot))
        *(.text .text.*)
    } :text

    . = ALIGN(PAGE_SIZE);
    .rodata : AT(KERNEL_LMA + (ADDR(.rodata) - KERNEL_VMA))
    {
        KEEP(*(.rodata.kernel_identity))
        *(.rodata .rodata.*)
    } :rodata

    . = ALIGN(PAGE_SIZE);
    .data : AT(KERNEL_LMA + (ADDR(.data) - KERNEL_VMA))
    {
        *(.data .data.*)
    } :data

    . = ALIGN(PAGE_SIZE);
    .bss (NOLOAD) : AT(KERNEL_LMA + (ADDR(.bss) - KERNEL_VMA))
    {
        __bss_start = .;
        *(.bss.stack)
        *(.bss .bss.*)
        *(COMMON)
        __bss_end = .;
    } :data

    . = ALIGN(PAGE_SIZE);
    __kernel_virtual_end = .;
    __kernel_physical_end = KERNEL_LMA + (__kernel_virtual_end - KERNEL_VMA);

    /DISCARD/ :
    {
        *(.comment)
        *(.eh_frame .eh_frame.*)
        *(.note .note.*)
    }
}

ASSERT((_start >= KERNEL_VMA), "kernel entry must be in the higher half")
ASSERT((__kernel_virtual_end - __kernel_virtual_start) < 0x04000000,
       "early kernel image must remain smaller than 64 MiB")
