#include <kernel/console.h>
#include <kernel/gdt.h>
#include <kernel/interrupts.h>
#include <kernel/pic.h>
#include <kernel/string.h>
#include <kernel/timer.h>
#include <kernel/keyboard.h>

#define IDT_ENTRY_COUNT 256U
#define IDT_INTERRUPT_GATE 0x8eU
#define DOUBLE_FAULT_VECTOR 8U
#define PAGE_FAULT_VECTOR 14U

#ifndef KERNEL_TEST_MODE
#define KERNEL_TEST_MODE 0
#endif

#define KERNEL_TEST_UNMAPPED_PAGE 2
#define KERNEL_TEST_READ_ONLY_PAGE 3
#define KERNEL_TEST_NX_PAGE 4
#define KERNEL_VM_TEST_BASE 0xffffc00000000000ULL

struct __attribute__((packed)) idt_entry {
    u16 offset_low;
    u16 selector;
    u8 ist;
    u8 type_attributes;
    u16 offset_middle;
    u32 offset_high;
    u32 reserved;
};

struct __attribute__((packed)) idt_pointer {
    u16 limit;
    u64 base;
};

typedef void (*interrupt_stub)(void);

extern interrupt_stub isr_stub_table[48];
extern void isr_unhandled(void);
extern void arch_idt_load(const struct idt_pointer *pointer);

static struct idt_entry kernel_idt[IDT_ENTRY_COUNT] __attribute__((aligned(16)));

_Static_assert(sizeof(struct idt_entry) == 16, "x86_64 IDT entry must be 16 bytes");
_Static_assert(sizeof(struct interrupt_frame) == 160,
               "C interrupt frame must match the assembly entry layout");

static const char *const exception_names[32] = {
    "Divide Error", "Debug", "Non-maskable Interrupt", "Breakpoint",
    "Overflow", "BOUND Range Exceeded", "Invalid Opcode", "Device Not Available",
    "Double Fault", "Coprocessor Segment Overrun", "Invalid TSS", "Segment Not Present",
    "Stack-Segment Fault", "General Protection Fault", "Page Fault", "Reserved",
    "x87 Floating-Point Exception", "Alignment Check", "Machine Check", "SIMD Exception",
    "Virtualization Exception", "Control Protection Exception", "Reserved", "Reserved",
    "Reserved", "Reserved", "Reserved", "Reserved", "Hypervisor Injection Exception",
    "VMM Communication Exception", "Security Exception", "Reserved"
};

static void idt_set_gate(u32 vector, interrupt_stub stub, u8 ist)
{
    const u64 address = (u64)(uptr)stub;
    struct idt_entry *entry = &kernel_idt[vector];

    entry->offset_low = (u16)address;
    entry->selector = GDT_KERNEL_CODE_SELECTOR;
    entry->ist = ist & 0x07U;
    entry->type_attributes = IDT_INTERRUPT_GATE;
    entry->offset_middle = (u16)(address >> 16U);
    entry->offset_high = (u32)(address >> 32U);
    entry->reserved = 0U;
}

void interrupts_init(void)
{
    struct idt_pointer pointer;
    u32 vector;

    memset(kernel_idt, 0, sizeof(kernel_idt));
    for (vector = 0U; vector < IDT_ENTRY_COUNT; ++vector) {
        idt_set_gate(vector, isr_unhandled, 0U);
    }
    for (vector = 0U; vector < 48U; ++vector) {
        idt_set_gate(vector, isr_stub_table[vector],
                     vector == DOUBLE_FAULT_VECTOR ? 1U : 0U);
    }

    pointer.limit = sizeof(kernel_idt) - 1U;
    pointer.base = (u64)(uptr)kernel_idt;
    arch_idt_load(&pointer);
    console_write("K3:IDT OK\n");
}

static __attribute__((noreturn)) void exception_halt(struct interrupt_frame *frame)
{
    u64 cr2 = 0U;
    const char *name = frame->vector < 32U ? exception_names[frame->vector] : "Unknown";

    if (frame->vector == PAGE_FAULT_VECTOR) {
        __asm__ volatile("movq %%cr2, %0" : "=r"(cr2));
    }

    console_printf("K3:EXCEPTION vector=%llu name=%s error=0x%llx\n",
                   frame->vector, name, frame->error_code);
    console_printf("K3:REG rip=0x%llx cs=0x%llx rflags=0x%llx\n",
                   frame->rip, frame->cs, frame->rflags);
    console_printf("K3:REG rax=0x%llx rbx=0x%llx rcx=0x%llx rdx=0x%llx\n",
                   frame->rax, frame->rbx, frame->rcx, frame->rdx);
    console_printf("K3:REG rsi=0x%llx rdi=0x%llx rbp=0x%llx\n",
                   frame->rsi, frame->rdi, frame->rbp);
    console_printf("K3:REG r8=0x%llx r9=0x%llx r10=0x%llx r11=0x%llx\n",
                   frame->r8, frame->r9, frame->r10, frame->r11);
    console_printf("K3:REG r12=0x%llx r13=0x%llx r14=0x%llx r15=0x%llx\n",
                   frame->r12, frame->r13, frame->r14, frame->r15);
    if (frame->vector == 0U) {
        console_write("K3:DIVIDE ERROR OK\n");
    }
    if (frame->vector == PAGE_FAULT_VECTOR) {
        console_printf("K3:PAGE FAULT cr2=0x%llx\n", cr2);
        console_write("K3:PAGE FAULT OK\n");
#if KERNEL_TEST_MODE == KERNEL_TEST_UNMAPPED_PAGE
        if (cr2 == KERNEL_VM_TEST_BASE && frame->error_code == 0ULL) {
            console_write("K4:UNMAPPED FAULT OK error=0x0\n");
        }
#elif KERNEL_TEST_MODE == KERNEL_TEST_READ_ONLY_PAGE
        if (cr2 == KERNEL_VM_TEST_BASE && frame->error_code == 0x3ULL) {
            console_write("K4:READONLY FAULT OK error=0x3\n");
        }
#elif KERNEL_TEST_MODE == KERNEL_TEST_NX_PAGE
        if (cr2 == KERNEL_VM_TEST_BASE && frame->error_code == 0x11ULL) {
            console_write("K4:NX FAULT OK error=0x11\n");
        }
#endif
    }
    panic("fatal exception");
}

void interrupt_dispatch(struct interrupt_frame *frame)
{
    if (frame->vector < 32U) {
        exception_halt(frame);
    }
    if (frame->vector == INTERRUPT_VECTOR_TIMER) {
        pit_on_irq();
    } else if (frame->vector == INTERRUPT_VECTOR_KEYBOARD) {
        keyboard_on_irq();
    } else if (frame->vector < INTERRUPT_VECTOR_PIC_BASE || frame->vector >= 48U) {
        panic("unhandled interrupt vector %llu", frame->vector);
    }

    pic_send_eoi((u8)(frame->vector - INTERRUPT_VECTOR_PIC_BASE));
}
