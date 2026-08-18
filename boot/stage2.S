#ifndef KERNEL_FILE_SIZE
#error "KERNEL_FILE_SIZE must be supplied by the Makefile"
#endif

#ifndef KERNEL_SECTORS
#error "KERNEL_SECTORS must be supplied by the Makefile"
#endif

.section .text

/* M1 handoff contract: stage1 validates these bytes and enters at physical 0x8004. */
.ascii "S2OK"

.code16
.global stage2_entry

.equ COM1_BASE,                  0x3f8
.equ STAGE2_PHYS,                0x00008000
.equ BOOT_INFO_PHYS,             0x00018000
.equ BOOT_INFO_SEGMENT,          0x1800
.equ BOOT_INFO_SIZE,             64
.equ E820_BUFFER_PHYS,           0x00018100
.equ E820_BUFFER_SEGMENT,        0x1810
.equ E820_ENTRY_SIZE,            24
.equ E820_MAX_ENTRIES,           64
.equ KERNEL_STAGING_PHYS,        0x00020000
.equ KERNEL_STAGING_SEGMENT,     0x2000
.equ KERNEL_STAGING_LIMIT,       0x00060000
.equ PML4_PHYS,                  0x00060000
.equ LOW_PDPT_PHYS,              0x00061000
.equ LOW_PD_PHYS,                0x00062000
.equ HIGH_PDPT_PHYS,             0x00063000
.equ HIGH_PD_PHYS,               0x00064000
.equ HIGH_PT_BASE_PHYS,          0x00065000
.equ HIGH_PT_COUNT,              32
.equ HIGH_PTE_COUNT,             (HIGH_PT_COUNT * 512)
.equ PAGE_TABLE_END_PHYS,        0x00085000
.equ TRANSITION_STACK_TOP,       0x0008f000
.equ KERNEL_LBA,                 128
.equ BIOS_MAX_READ_SECTORS,      127
.equ DISK_READ_RETRIES,          3
.equ KERNEL_PHYS_MIN_ALLOWED,    0x00100000
.equ KERNEL_PHYS_MAX_EXCLUSIVE,  0x04100000
.equ KERNEL_VIRT_BASE_LOW,       0x80000000

.equ BOOT_INFO_VERSION_OFFSET,       0
.equ BOOT_INFO_SIZE_OFFSET,          4
.equ BOOT_INFO_DRIVE_OFFSET,         8
.equ BOOT_INFO_E820_COUNT_OFFSET,    12
.equ BOOT_INFO_E820_PTR_OFFSET,      16
.equ BOOT_INFO_PHYS_START_OFFSET,    24
.equ BOOT_INFO_PHYS_END_OFFSET,      32
.equ BOOT_INFO_VIRT_START_OFFSET,    40
.equ BOOT_INFO_VIRT_END_OFFSET,      48
.equ BOOT_INFO_ENTRY_OFFSET,         56

.equ CODE32_SELECTOR,            0x08
.equ DATA32_SELECTOR,            0x10
.equ CODE64_SELECTOR,            0x18
.equ DATA64_SELECTOR,            0x20

stage2_entry:
    cli
    xorw %ax, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    movw $0x7c00, %sp
    sti
    cld

    movb %dl, boot_drive
    movw $message_stage2, %si
    call print_string16

    call enable_a20
    call initialize_boot_info
    call collect_e820
    jc e820_error16
    movw $message_e820_ok, %si
    call print_string16

    call read_kernel_elf
    jc disk_error16

    cli
    lgdt gdt_descriptor
    movl %cr0, %eax
    orl $0x00000001, %eax
    movl %eax, %cr0
    ljmpl $CODE32_SELECTOR, $protected_mode_entry

e820_error16:
    movw $message_e820_error, %si
    call print_string16
    jmp halt16

disk_error16:
    movw $message_kernel_disk_error, %si
    call print_string16

halt16:
    cli
1:
    hlt
    jmp 1b

enable_a20:
    inb $0x92, %al
    orb $0x02, %al
    andb $0xfe, %al
    outb %al, $0x92
    ret

initialize_boot_info:
    pushw %es
    movw $BOOT_INFO_SEGMENT, %ax
    movw %ax, %es
    xorw %di, %di
    xorw %ax, %ax
    movw $(BOOT_INFO_SIZE / 2), %cx
    rep stosw

    movl $1, %es:BOOT_INFO_VERSION_OFFSET
    movl $BOOT_INFO_SIZE, %es:BOOT_INFO_SIZE_OFFSET
    movzbl boot_drive, %eax
    movl %eax, %es:BOOT_INFO_DRIVE_OFFSET
    movl $E820_BUFFER_PHYS, %es:BOOT_INFO_E820_PTR_OFFSET
    movl $0, %es:(BOOT_INFO_E820_PTR_OFFSET + 4)
    popw %es
    ret

collect_e820:
    pushw %es
    movw $E820_BUFFER_SEGMENT, %ax
    movw %ax, %es
    xorw %di, %di
    xorw %bp, %bp
    xorl %ebx, %ebx

2:
    movl $1, %es:20(%di)
    movl $0xe820, %eax
    movl $0x534d4150, %edx
    movl $E820_ENTRY_SIZE, %ecx
    int $0x15
    jc 4f
    cmpl $0x534d4150, %eax
    jne 5f
    cmpw $20, %cx
    jb 5f

    movl %es:8(%di), %eax
    orl %es:12(%di), %eax
    jz 3f
    incw %bp
    addw $E820_ENTRY_SIZE, %di
    cmpw $E820_MAX_ENTRIES, %bp
    jae 4f

3:
    testl %ebx, %ebx
    jnz 2b

4:
    testw %bp, %bp
    jz 5f
    movw $BOOT_INFO_SEGMENT, %ax
    movw %ax, %es
    movzwl %bp, %eax
    movl %eax, %es:BOOT_INFO_E820_COUNT_OFFSET
    popw %es
    clc
    ret

5:
    popw %es
    stc
    ret

read_kernel_elf:
    movw $KERNEL_SECTORS, kernel_remaining_sectors
    movl $KERNEL_LBA, kernel_current_lba
    movw $KERNEL_STAGING_SEGMENT, kernel_destination_segment

6:
    movw kernel_remaining_sectors, %ax
    testw %ax, %ax
    jz 10f
    cmpw $BIOS_MAX_READ_SECTORS, %ax
    jbe 7f
    movw $BIOS_MAX_READ_SECTORS, %ax
7:
    movw %ax, kernel_chunk_sectors
    movw %ax, kernel_dap + 2
    movw $0, kernel_dap + 4
    movw kernel_destination_segment, %ax
    movw %ax, kernel_dap + 6
    movl kernel_current_lba, %eax
    movl %eax, kernel_dap + 8
    movl $0, kernel_dap + 12
    movb $DISK_READ_RETRIES, kernel_read_retries

8:
    movb boot_drive, %dl
    movw $kernel_dap, %si
    movb $0x42, %ah
    int $0x13
    jnc 9f
    movb boot_drive, %dl
    xorb %ah, %ah
    int $0x13
    decb kernel_read_retries
    jnz 8b
    stc
    ret

9:
    movw kernel_chunk_sectors, %ax
    subw %ax, kernel_remaining_sectors
    movzwl %ax, %eax
    addl %eax, kernel_current_lba
    shlw $5, %ax
    addw %ax, kernel_destination_segment
    jmp 6b

10:
    clc
    ret

print_string16:
    lodsb
    testb %al, %al
    jz 12f
    call put_char16
    jmp print_string16
12:
    ret

put_char16:
    pushw %ax
    pushw %bx
    pushw %dx
    movb %al, %bl

    movb $0x0e, %ah
    xorb %bh, %bh
    int $0x10

    movw $COM1_BASE + 5, %dx
13:
    inb %dx, %al
    testb $0x20, %al
    jz 13b
    movw $COM1_BASE, %dx
    movb %bl, %al
    outb %al, %dx

    popw %dx
    popw %bx
    popw %ax
    ret

boot_drive:
    .byte 0
kernel_read_retries:
    .byte 0
.balign 2
kernel_remaining_sectors:
    .word 0
kernel_chunk_sectors:
    .word 0
kernel_destination_segment:
    .word 0
.balign 4
kernel_current_lba:
    .long 0

message_stage2:
    .asciz "S2\r\n"
message_e820_ok:
    .asciz "M2:E820 OK\r\n"
message_e820_error:
    .asciz "M2:E820 ERROR\r\n"
message_kernel_disk_error:
    .asciz "M2:DISK ERROR\r\n"

.balign 4
kernel_dap:
    .byte 0x10
    .byte 0x00
    .word 0
    .word 0
    .word 0
    .quad 0

.balign 8
gdt_start:
    .quad 0x0000000000000000
    .quad 0x00cf9a000000ffff
    .quad 0x00cf92000000ffff
    .quad 0x00af9a000000ffff
    .quad 0x00af92000000ffff
gdt_end:

gdt_descriptor:
    .word gdt_end - gdt_start - 1
    .long gdt_start

/* -------------------------------------------------------------------------- */
/* 32-bit protected mode: validate/copy ELF and prepare long-mode page tables. */
/* -------------------------------------------------------------------------- */

.code32
protected_mode_entry:
    movw $DATA32_SELECTOR, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    movw %ax, %fs
    movw %ax, %gs
    movl $TRANSITION_STACK_TOP, %esp
    cld

    call check_long_mode_support
    jc long_mode_error32
    call validate_kernel_elf
    jc elf_error32
    call check_kernel_memory
    jc memory_error32
    call load_kernel_segments
    jc elf_error32
    call build_page_tables

    movl $message_elf_ok, %esi
    call print_string32

    movl %cr4, %eax
    orl $0x00000020, %eax
    movl %eax, %cr4

    movl $0xc0000080, %ecx
    rdmsr
    orl $0x00000100, %eax
    wrmsr

    movl $PML4_PHYS, %eax
    movl %eax, %cr3

    movl %cr0, %eax
    orl $0x80000000, %eax
    movl %eax, %cr0
    ljmpl $CODE64_SELECTOR, $long_mode_entry

long_mode_error32:
    movl $message_long_mode_error, %esi
    jmp fatal32

elf_error32:
    movl $message_elf_error, %esi
    jmp fatal32

memory_error32:
    movl $message_memory_error, %esi

fatal32:
    call print_string32
    cli
14:
    hlt
    jmp 14b

check_long_mode_support:
    movl $0x80000000, %eax
    cpuid
    cmpl $0x80000001, %eax
    jb 15f
    movl $0x80000001, %eax
    cpuid
    testl $0x20000000, %edx
    jz 15f
    clc
    ret
15:
    stc
    ret

validate_kernel_elf:
    cmpl $0x464c457f, KERNEL_STAGING_PHYS
    jne 29f
    cmpb $2, KERNEL_STAGING_PHYS + 4
    jne 29f
    cmpb $1, KERNEL_STAGING_PHYS + 5
    jne 29f
    cmpb $1, KERNEL_STAGING_PHYS + 6
    jne 29f
    cmpw $2, KERNEL_STAGING_PHYS + 16
    jne 29f
    cmpw $62, KERNEL_STAGING_PHYS + 18
    jne 29f
    cmpl $1, KERNEL_STAGING_PHYS + 20
    jne 29f
    cmpw $64, KERNEL_STAGING_PHYS + 52
    jne 29f
    cmpw $56, KERNEL_STAGING_PHYS + 54
    jne 29f

    cmpl $0, KERNEL_STAGING_PHYS + 36
    jne 29f
    movl KERNEL_STAGING_PHYS + 32, %eax
    cmpl $64, %eax
    jb 29f
    movl %eax, kernel_phoff

    movzwl KERNEL_STAGING_PHYS + 56, %ecx
    testl %ecx, %ecx
    jz 29f
    cmpl $32, %ecx
    ja 29f
    movl %ecx, kernel_phnum
    imull $56, %ecx, %edx
    addl %eax, %edx
    jc 29f
    cmpl $KERNEL_FILE_SIZE, %edx
    ja 29f

    movl KERNEL_STAGING_PHYS + 24, %eax
    movl KERNEL_STAGING_PHYS + 28, %edx
    cmpl $0xffffffff, %edx
    jne 29f
    cmpl $KERNEL_VIRT_BASE_LOW, %eax
    jb 29f
    movl %eax, kernel_entry_low
    movl %edx, kernel_entry_high

    movl $0xffffffff, kernel_phys_start
    movl $0, kernel_phys_end
    movl $0xffffffff, kernel_virt_start_low
    movl $0, kernel_virt_end_low
    movl $0, kernel_load_count
    movb $0, kernel_entry_valid

    movl kernel_phoff, %edi
    addl $KERNEL_STAGING_PHYS, %edi
    movl kernel_phnum, %ecx

16:
    cmpl $1, 0(%edi)
    jne 27f

    cmpl $0, 12(%edi)
    jne 29f
    cmpl $0, 28(%edi)
    jne 29f
    cmpl $0, 36(%edi)
    jne 29f
    cmpl $0, 44(%edi)
    jne 29f
    cmpl $0xffffffff, 20(%edi)
    jne 29f

    movl 16(%edi), %eax
    cmpl $KERNEL_VIRT_BASE_LOW, %eax
    jb 29f
    movl 24(%edi), %edx
    cmpl $KERNEL_PHYS_MIN_ALLOWED, %edx
    jb 29f

    movl 32(%edi), %ebx
    movl 40(%edi), %ebp
    cmpl %ebx, %ebp
    jb 29f

    movl 8(%edi), %esi
    addl %ebx, %esi
    jc 29f
    cmpl $KERNEL_FILE_SIZE, %esi
    ja 29f

    movl %edx, %esi
    addl %ebp, %esi
    jc 29f
    cmpl $KERNEL_PHYS_MAX_EXCLUSIVE, %esi
    ja 29f

    cmpl kernel_phys_start, %edx
    jae 17f
    movl %edx, kernel_phys_start
17:
    cmpl kernel_phys_end, %esi
    jbe 18f
    movl %esi, kernel_phys_end

18:
    cmpl kernel_virt_start_low, %eax
    jae 19f
    movl %eax, kernel_virt_start_low
19:
    movl %eax, %esi
    addl %ebp, %esi
    jc 29f
    cmpl kernel_virt_end_low, %esi
    jbe 20f
    movl %esi, kernel_virt_end_low

20:
    incl kernel_load_count
    testl $1, 4(%edi)
    jz 27f
    movl kernel_entry_low, %esi
    cmpl %eax, %esi
    jb 27f
    movl %eax, %edx
    addl %ebp, %edx
    jc 29f
    cmpl %edx, %esi
    jae 27f
    movb $1, kernel_entry_valid

27:
    addl $56, %edi
    decl %ecx
    jnz 16b

    cmpl $0, kernel_load_count
    je 29f
    cmpb $1, kernel_entry_valid
    jne 29f
    clc
    ret

29:
    stc
    ret

check_kernel_memory:
    movl BOOT_INFO_PHYS + BOOT_INFO_E820_COUNT_OFFSET, %ecx
    movl $E820_BUFFER_PHYS, %esi

30:
    testl %ecx, %ecx
    jz 35f
    cmpl $1, 16(%esi)
    jne 34f
    cmpl $0, 4(%esi)
    jne 34f
    movl 0(%esi), %eax
    cmpl kernel_phys_start, %eax
    ja 34f

    movl 8(%esi), %edx
    movl 12(%esi), %ebx
    addl %eax, %edx
    adcl $0, %ebx
    testl %ebx, %ebx
    jnz 33f
    cmpl kernel_phys_end, %edx
    jb 34f
33:
    clc
    ret

34:
    addl $E820_ENTRY_SIZE, %esi
    decl %ecx
    jmp 30b

35:
    stc
    ret

load_kernel_segments:
    movl kernel_phoff, %ebp
    addl $KERNEL_STAGING_PHYS, %ebp
    movl kernel_phnum, %eax
    movl %eax, ph_remaining

36:
    cmpl $1, 0(%ebp)
    jne 37f
    movl 8(%ebp), %esi
    addl $KERNEL_STAGING_PHYS, %esi
    movl 24(%ebp), %edi
    movl 32(%ebp), %ecx
    rep movsb
    movl 40(%ebp), %ecx
    subl 32(%ebp), %ecx
    xorl %eax, %eax
    rep stosb
37:
    addl $56, %ebp
    decl ph_remaining
    jnz 36b

    movl kernel_phys_start, %eax
    movl %eax, BOOT_INFO_PHYS + BOOT_INFO_PHYS_START_OFFSET
    movl $0, BOOT_INFO_PHYS + BOOT_INFO_PHYS_START_OFFSET + 4
    movl kernel_phys_end, %eax
    movl %eax, BOOT_INFO_PHYS + BOOT_INFO_PHYS_END_OFFSET
    movl $0, BOOT_INFO_PHYS + BOOT_INFO_PHYS_END_OFFSET + 4
    movl kernel_virt_start_low, %eax
    movl %eax, BOOT_INFO_PHYS + BOOT_INFO_VIRT_START_OFFSET
    movl $0xffffffff, BOOT_INFO_PHYS + BOOT_INFO_VIRT_START_OFFSET + 4
    movl kernel_virt_end_low, %eax
    movl %eax, BOOT_INFO_PHYS + BOOT_INFO_VIRT_END_OFFSET
    movl $0xffffffff, BOOT_INFO_PHYS + BOOT_INFO_VIRT_END_OFFSET + 4
    movl kernel_entry_low, %eax
    movl %eax, BOOT_INFO_PHYS + BOOT_INFO_ENTRY_OFFSET
    movl kernel_entry_high, %eax
    movl %eax, BOOT_INFO_PHYS + BOOT_INFO_ENTRY_OFFSET + 4
    clc
    ret

build_page_tables:
    movl $PML4_PHYS, %edi
    xorl %eax, %eax
    movl $((PAGE_TABLE_END_PHYS - PML4_PHYS) / 4), %ecx
    rep stosl

    movl $(LOW_PDPT_PHYS | 0x003), PML4_PHYS
    movl $(HIGH_PDPT_PHYS | 0x003), PML4_PHYS + (511 * 8)
    movl $(LOW_PD_PHYS | 0x003), LOW_PDPT_PHYS
    movl $(HIGH_PD_PHYS | 0x003), HIGH_PDPT_PHYS + (510 * 8)

    movl $LOW_PD_PHYS, %edi
    movl $0x00000083, %eax
    movl $512, %ecx
38:
    movl %eax, 0(%edi)
    movl $0, 4(%edi)
    addl $0x00200000, %eax
    addl $8, %edi
    loop 38b

    movl $HIGH_PD_PHYS, %edi
    movl $(HIGH_PT_BASE_PHYS | 0x003), %eax
    movl $HIGH_PT_COUNT, %ecx
39:
    movl %eax, 0(%edi)
    movl $0, 4(%edi)
    addl $0x1000, %eax
    addl $8, %edi
    loop 39b

    movl $HIGH_PT_BASE_PHYS, %edi
    movl $(KERNEL_PHYS_MIN_ALLOWED | 0x003), %eax
    movl $HIGH_PTE_COUNT, %ecx
40:
    movl %eax, 0(%edi)
    movl $0, 4(%edi)
    addl $0x1000, %eax
    addl $8, %edi
    loop 40b
    ret

print_string32:
    lodsb
    testb %al, %al
    jz 42f
    movb %al, %bl
    movw $COM1_BASE + 5, %dx
41:
    inb %dx, %al
    testb $0x20, %al
    jz 41b
    movw $COM1_BASE, %dx
    movb %bl, %al
    outb %al, %dx
    jmp print_string32
42:
    ret

message_long_mode_error:
    .asciz "M2:LONG MODE ERROR\r\n"
message_elf_error:
    .asciz "M2:ELF ERROR\r\n"
message_memory_error:
    .asciz "M2:MEMORY ERROR\r\n"
message_elf_ok:
    .asciz "M2:ELF OK\r\n"

.balign 4
kernel_phoff:
    .long 0
kernel_phnum:
    .long 0
kernel_entry_low:
    .long 0
kernel_entry_high:
    .long 0
kernel_phys_start:
    .long 0
kernel_phys_end:
    .long 0
kernel_virt_start_low:
    .long 0
kernel_virt_end_low:
    .long 0
kernel_load_count:
    .long 0
ph_remaining:
    .long 0
kernel_entry_valid:
    .byte 0

/* -------------------------------------------------------------------------- */
/* 64-bit mode: pass boot_info in RDI and jump to the entry read from the ELF. */
/* -------------------------------------------------------------------------- */

.balign 16
.code64
long_mode_entry:
    movw $DATA64_SELECTOR, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    movw %ax, %fs
    movw %ax, %gs
    movq $TRANSITION_STACK_TOP, %rsp
    xorq %rbp, %rbp
    movq $BOOT_INFO_PHYS, %rdi
    movq BOOT_INFO_ENTRY_OFFSET(%rdi), %rax
    jmp *%rax

.section .note.GNU-stack, "", @progbits
