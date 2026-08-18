#include <kernel/console.h>
#include <kernel/gdt.h>
#include <kernel/string.h>
#include <kernel/types.h>

struct __attribute__((packed)) tss64 {
    u32 reserved0;
    u64 rsp0;
    u64 rsp1;
    u64 rsp2;
    u64 reserved1;
    u64 ist1;
    u64 ist2;
    u64 ist3;
    u64 ist4;
    u64 ist5;
    u64 ist6;
    u64 ist7;
    u64 reserved2;
    u16 reserved3;
    u16 io_map_base;
};

struct __attribute__((packed)) gdt_pointer {
    u16 limit;
    u64 base;
};

struct __attribute__((packed)) gdt_table {
    u64 null_descriptor;
    u64 code_descriptor;
    u64 data_descriptor;
    u64 tss_descriptor_low;
    u64 tss_descriptor_high;
};

extern u8 bootstrap_stack_top[];
extern void arch_gdt_load(const struct gdt_pointer *pointer,
                          u16 code_selector,
                          u16 data_selector,
                          u16 tss_selector);

static struct tss64 kernel_tss;
static struct gdt_table kernel_gdt __attribute__((aligned(16)));
static u8 double_fault_stack[16384] __attribute__((aligned(16)));

_Static_assert(sizeof(struct tss64) == 104, "x86_64 TSS must be 104 bytes");
_Static_assert(sizeof(struct gdt_table) == 40, "kernel GDT layout must be 40 bytes");

static void gdt_set_tss_descriptor(struct gdt_table *gdt, const struct tss64 *tss)
{
    const u64 base = (u64)(uptr)tss;
    const u64 limit = sizeof(*tss) - 1U;

    gdt->tss_descriptor_low =
        (limit & 0xffffU) |
        ((base & 0xffffffU) << 16U) |
        (0x89ULL << 40U) |
        (((limit >> 16U) & 0x0fU) << 48U) |
        (((base >> 24U) & 0xffU) << 56U);
    gdt->tss_descriptor_high = base >> 32U;
}

void gdt_init(void)
{
    struct gdt_pointer pointer;

    memset(&kernel_tss, 0, sizeof(kernel_tss));
    kernel_tss.rsp0 = (u64)(uptr)bootstrap_stack_top;
    kernel_tss.ist1 = (u64)(uptr)(double_fault_stack + sizeof(double_fault_stack));
    kernel_tss.io_map_base = sizeof(kernel_tss);

    memset(&kernel_gdt, 0, sizeof(kernel_gdt));
    kernel_gdt.code_descriptor = 0x00af9a000000ffffULL;
    kernel_gdt.data_descriptor = 0x00cf92000000ffffULL;
    gdt_set_tss_descriptor(&kernel_gdt, &kernel_tss);

    pointer.limit = sizeof(kernel_gdt) - 1U;
    pointer.base = (u64)(uptr)&kernel_gdt;
    arch_gdt_load(&pointer,
                  GDT_KERNEL_CODE_SELECTOR,
                  GDT_KERNEL_DATA_SELECTOR,
                  GDT_TSS_SELECTOR);
    console_write("K3:GDT TSS OK\n");
}
