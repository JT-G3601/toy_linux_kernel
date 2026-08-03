/* 输出 x86_64 ELF，并把 entry.S 中的 _start 写入 ELF header 作为入口。 */
OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)
ENTRY(_start)

/*
 * VMA（Virtual Memory Address）是开启分页后 CPU 用来访问内核的高地址。
 * LMA（Load Memory Address）是 bootloader 把 ELF segment 放入 RAM 的低物理地址。
 * 两者的连接由 M2 的页表建立：0xffffffff80000000 -> 0x00100000。
 *
 * 注意：LMA 不是 kernel.elf 在磁盘镜像里的位置。磁盘位置由 Makefile 中的
 * KERNEL_DISK_OFFSET 独立规定，当前是 65536 字节（LBA 128）。
 */
KERNEL_VMA = 0xffffffff80000000;
KERNEL_LMA = 0x00100000;
PAGE_SIZE = 0x1000;

/*
 * ELF program headers。PT_LOAD 告诉 loader 这些 segment 需要装入内存。
 * FLAGS 是 ELF 权限位的和：R=4、W=2、X=1，因此：
 *   text   = 5 = R|X（代码可读可执行）
 *   rodata = 4 = R  （常量只读）
 *   data   = 6 = R|W（数据可读可写）
 * 分开它们可以避免产生同时可写又可执行的 W+X segment。
 */
PHDRS
{
    text   PT_LOAD FLAGS(5);
    rodata PT_LOAD FLAGS(4);
    data   PT_LOAD FLAGS(6);
}

SECTIONS
{
    /* `.` 是 location counter；从 higher-half 虚拟地址开始排列各 section。 */
    . = KERNEL_VMA;

    /* 导出内核虚拟/物理起点，供后续内核代码引用。 */
    __kernel_virtual_start = .;
    __kernel_physical_start = KERNEL_LMA;

    /*
     * 代码的 VMA 从 KERNEL_VMA 开始，AT(KERNEL_LMA) 指定它的物理加载地址。
     * KEEP 保证入口 section 不会被链接器的 --gc-sections 删除。
     * `*(.text .text.*)` 收集所有输入目标文件中的代码 section。
     * 末尾的 `:text` 把输出 section 放入上面定义的 text program segment。
     */
    .text : AT(KERNEL_LMA)
    {
        KEEP(*(.text.boot))
        *(.text .text.*)
    } :text

    /* 每类内容从 4 KiB 页边界开始，便于页表设置不同权限。 */
    . = ALIGN(PAGE_SIZE);

    /*
     * ADDR(.rodata) 是 rodata 的 VMA。减去 KERNEL_VMA 得到相对内核起点的偏移，
     * 再加 KERNEL_LMA 得到对应 LMA：
     *   section LMA = KERNEL_LMA + (section VMA - KERNEL_VMA)
     * 这样物理布局和虚拟布局保持相同的相对偏移。
     */
    .rodata : AT(KERNEL_LMA + (ADDR(.rodata) - KERNEL_VMA))
    {
        /* 保留项目的内核身份字符串，再收集其他只读常量。 */
        KEEP(*(.rodata.kernel_identity))
        *(.rodata .rodata.*)
    } :rodata

    . = ALIGN(PAGE_SIZE);

    /* 收集已初始化的可写全局/静态数据，放入 R|W segment。 */
    .data : AT(KERNEL_LMA + (ADDR(.data) - KERNEL_VMA))
    {
        *(.data .data.*)
    } :data

    . = ALIGN(PAGE_SIZE);

    /*
     * BSS 为未初始化数据和 bootstrap stack 保留内存。NOLOAD 表示这部分不需
     * 在 ELF 文件中存放成片的零；loader 需要确保对应内存为零。
     * __bss_start/__bss_end 标记了需要清零的范围。
     */
    .bss (NOLOAD) : AT(KERNEL_LMA + (ADDR(.bss) - KERNEL_VMA))
    {
        __bss_start = .;
        /* 先放 entry.S 中的 16 KiB bootstrap stack。 */
        *(.bss.stack)
        *(.bss .bss.*)
        /* COMMON 兼容工具链可能产生的旧式未初始化公共符号。 */
        *(COMMON)
        __bss_end = .;
    } :data

    . = ALIGN(PAGE_SIZE);

    /* 导出页对齐后的内核虚拟/物理结束地址。 */
    __kernel_virtual_end = .;
    __kernel_physical_end = KERNEL_LMA + (__kernel_virtual_end - KERNEL_VMA);

    /* 丢弃早期 freestanding 内核不需要的编译器注释、unwind 和 note 元数据。 */
    /DISCARD/ :
    {
        *(.comment)
        *(.eh_frame .eh_frame.*)
        *(.note .note.*)
    }
}

/* 让不符合启动契约的布局在链接期立即失败。 */
ASSERT((_start >= KERNEL_VMA), "kernel entry must be in the higher half")
ASSERT((__kernel_virtual_end - __kernel_virtual_start) < 0x04000000,
       "early kernel image must remain smaller than 64 MiB")
