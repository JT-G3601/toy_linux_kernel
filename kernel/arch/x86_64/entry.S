.section .text.boot, "ax", @progbits
.global _start
.type _start, @function
.extern kernel_main

_start:
    cli
    leaq bootstrap_stack_top(%rip), %rsp
    xorq %rbp, %rbp
    call kernel_main

.Lhalt:
    hlt
    jmp .Lhalt

.size _start, . - _start

.section .bss.stack, "aw", @nobits
.balign 16
.global bootstrap_stack_bottom
bootstrap_stack_bottom:
    .skip 16384
.global bootstrap_stack_top
bootstrap_stack_top:

.section .note.GNU-stack, "", @progbits
