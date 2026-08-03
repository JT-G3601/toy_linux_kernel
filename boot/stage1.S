.code16
.section .text
.global stage1_start

/* BIOS loads this sector at physical address 0x7c00 and leaves the boot drive in DL. */
.equ COM1_BASE,              0x3f8
.equ STAGE2_LOAD_SEGMENT,    0x0800
.equ STAGE2_ENTRY_OFFSET,    4
.equ STAGE2_LBA,             1
.equ STAGE2_SECTORS,         127
.equ READ_RETRIES,           3

stage1_start:
    /* Normalize CS:IP because BIOS may enter as either 0000:7c00 or 07c0:0000. */
    ljmp $0x0000, $stage1_normalized

stage1_normalized:
    cli
    xorw %ax, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    movw $0x7c00, %sp
    sti
    cld

    movb %dl, boot_drive
    call serial_init
    movw $message_stage1, %si
    call print_string

    /* Require INT 13h extensions and the extended-read function used below. */
    movb boot_drive, %dl
    movw $0x55aa, %bx
    movb $0x41, %ah
    int $0x13
    jc disk_error
    cmpw $0xaa55, %bx
    jne disk_error
    testw $0x0001, %cx
    jz disk_error

    movb $READ_RETRIES, retries_left

read_stage2:
    movb boot_drive, %dl
    /* BIOS may update the DAP count after a partial failure; every retry requests all sectors. */
    movw $STAGE2_SECTORS, disk_address_packet + 2
    movw $disk_address_packet, %si
    movb $0x42, %ah
    int $0x13
    jnc validate_stage2

    /* Reset the BIOS disk service before retrying a failed extended read. */
    movb boot_drive, %dl
    xorb %ah, %ah
    int $0x13
    decb retries_left
    jnz read_stage2

disk_error:
    movw $message_disk_error, %si
    call print_string
    jmp halt

validate_stage2:
    /* Refuse to execute an absent or malformed stage2 header. */
    movw $STAGE2_LOAD_SEGMENT, %ax
    movw %ax, %es
    cmpw $0x3253, %es:0
    jne stage2_error
    cmpw $0x4b4f, %es:2
    jne stage2_error

    movb boot_drive, %dl
    ljmp $STAGE2_LOAD_SEGMENT, $STAGE2_ENTRY_OFFSET

stage2_error:
    movw $message_stage2_error, %si
    call print_string

halt:
    cli
1:
    hlt
    jmp 1b

/* Initialize COM1 for 115200 baud, 8 data bits, no parity, one stop bit. */
serial_init:
    movw $COM1_BASE + 1, %dx
    xorb %al, %al
    outb %al, %dx
    movw $COM1_BASE + 3, %dx
    movb $0x80, %al
    outb %al, %dx
    movw $COM1_BASE, %dx
    movb $0x01, %al
    outb %al, %dx
    movw $COM1_BASE + 1, %dx
    xorb %al, %al
    outb %al, %dx
    movw $COM1_BASE + 3, %dx
    movb $0x03, %al
    outb %al, %dx
    movw $COM1_BASE + 2, %dx
    movb $0xc7, %al
    outb %al, %dx
    movw $COM1_BASE + 4, %dx
    movb $0x0b, %al
    outb %al, %dx
    ret

/* Print a NUL-terminated DS:SI string to both BIOS VGA teletype and COM1. */
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

boot_drive:
    .byte 0
retries_left:
    .byte 0

message_stage1:
    .asciz "S1\r\n"
message_disk_error:
    .asciz "E1\r\n"
message_stage2_error:
    .asciz "E2\r\n"

/* INT 13h AH=42h disk address packet: load LBA 1..127 at 0800:0000 (physical 0x8000). */
.balign 4
disk_address_packet:
    .byte 0x10
    .byte 0x00
    .word STAGE2_SECTORS
    .word 0x0000
    .word STAGE2_LOAD_SEGMENT
    .quad STAGE2_LBA

/* `.org` fails assembly if code grows beyond byte 510; the final word is the BIOS signature. */
.org 510, 0
.word 0xaa55

.section .note.GNU-stack, "", @progbits
