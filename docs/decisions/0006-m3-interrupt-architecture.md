# ADR-0006：M3 内核描述符表与中断向量契约

- 状态：accepted
- 日期：2026-08-18

## 背景

M2 只用 loader 的临时 GDT 进入 long mode，并在关中断状态下调用内核。M3 开始
接收 CPU 异常和外部 IRQ，因此内核必须拥有自己的 GDT、TSS、IDT、统一寄存器帧、
PIC vector 分配和可重复测试入口。若这些值散落在汇编和 C 中，selector、错误码、
寄存器顺序或 EOI 规则的偏差会直接导致 double/triple fault，且串口通常来不及输出。

## 决策

### GDT 与 TSS

内核 GDT 固定为 40 bytes：

| index | selector | descriptor |
|---:|---:|---|
| 0 | `0x00` | null |
| 1 | `0x08` | ring 0 64-bit code |
| 2 | `0x10` | ring 0 data |
| 3-4 | `0x18` | 16-byte 64-bit available TSS |

TSS 的 `RSP0` 指向 bootstrap stack 顶部，`IST1` 指向独立 16 KiB double-fault
stack。IDT vector 8 使用 IST1；M3 尚无 ring 3，因此 `RSP0` 只固定未来 CPL 切换
契约，当前普通异常/IRQ 不发生 privilege stack switch。

### IDT、vector 与中断帧

- IDT 有 256 个 16-byte interrupt gate，gate selector 为 `0x08`，DPL 为 0。
- CPU exceptions 使用 vector `0..31`。
- 8259 PIC remap 到 master `32..39`、slave `40..47`，避免与 CPU exceptions 重叠。
- PIT 使用 IRQ0/vector 32，PS/2 keyboard 使用 IRQ1/vector 33；M3 只 unmask IRQ0/1。
- 未专门注册的 vector 指向统一 unhandled stub，并作为 vector 255 报告后 panic。
- 汇编 stub 为没有硬件 error code 的 vector 补一个 0，再压入 vector number，使 C
  始终看到相同前缀。

`struct interrupt_frame` 从低地址到高地址固定为：

```text
r15 r14 r13 r12 r11 r10 r9 r8
rsi rdi rbp rdx rcx rbx rax
vector error_code rip cs rflags
```

当前结构只描述 CPL0 -> CPL0 的 entry，CPU 不会额外压入旧 `rsp/ss`。M6 引入
ring 3 时必须扩展入口契约并处理 `swapgs`、用户栈和用户指针边界，不能直接假定
本帧覆盖 privilege transition。

### 设备与测试

- 8254-compatible PIT channel 0 配置为 rate generator，目标频率 100 Hz。
- PS/2 keyboard 读取 data port `0x60`，第一版只转换 set-1 单字节 make codes、
  左/右 Shift 和基本 ASCII；release、扩展键、LED、布局切换留到后续。
- console 同时写 COM1 和 VGA text buffer；异常路径先关中断再打印并 halt。
- `KERNEL_TEST_MODE=0/1/2` 分别构建正常、真实 divide error、真实 page fault 镜像。
  `make test-boot` 通过 QEMU HMP `sendkey a` 注入键盘输入，同时保留 M2 三条负路径。

## 影响

- M3 能观察 PIT tick、键盘 IRQ、exception vector/error code、CR2 和通用寄存器。
- TSS/IST 为 double fault 提供独立栈，但 M3 不尝试从 fatal exception 恢复。
- 8259/PIT/PS2 是 Legacy PC 教学路径；后续可增加 APIC/IOAPIC、HPET/LAPIC timer
  和更完整输入层，但必须保留或正式 supersede 本 ADR 的 vector/frame 契约。
- 中断处理目前是单核、无锁、无嵌套设计；进入 SMP 或抢占前必须增加 per-CPU
  descriptor tables、同步和更严格的 entry/exit 规则。
