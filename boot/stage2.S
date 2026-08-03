.code16
.section .text
.global stage2_entry

.equ COM1_BASE, 0x3f8

/* Stage1 validates this header and enters at 0800:0004 (physical address 0x8004). */
.ascii "S2OK"

stage2_entry:
    cli
    movw %cs, %ax
    movw %ax, %ds
    movw %ax, %es
    xorw %ax, %ax
    movw %ax, %ss
    movw $0x7c00, %sp
    sti
    cld

    movw $message_stage2, %si
    call print_string

    /* M1 stops here. M2 replaces this stub with the ELF loader and long-mode transition. */
    cli
1:
    hlt
    jmp 1b

print_string:
    lodsb
    testb %al, %al
    jz 2f
    call put_char
    jmp print_string
2:
    ret

put_char:
    pushw %ax
    pushw %bx
    pushw %dx
    movb %al, %bl

    movb $0x0e, %ah
    xorb %bh, %bh
    int $0x10

    movw $COM1_BASE + 5, %dx
3:
    inb %dx, %al
    testb $0x20, %al
    jz 3b
    movw $COM1_BASE, %dx
    movb %bl, %al
    outb %al, %dx

    popw %dx
    popw %bx
    popw %ax
    ret

message_stage2:
    .asciz "S2\r\n"

/* Keep the M1 stub deterministic and sector-sized; M2 may grow up to the reserved 127 sectors. */
.org 512, 0

.section .note.GNU-stack, "", @progbits
