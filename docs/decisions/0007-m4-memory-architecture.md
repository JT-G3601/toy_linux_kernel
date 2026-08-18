# ADR-0007：M4 物理页、最终页表与内核堆契约

- 状态：accepted
- 日期：2026-08-18

## 背景

M2 页表只负责把 CPU 安全送入 higher-half 内核：低 1 GiB 全部 identity-map，内核
64 MiB 窗口统一 writable。M4 必须接管 E820 可用内存、收紧内核权限，并在移除
临时低映射后继续访问页表和设备。PMM、VMM 与堆若没有固定地址和所有权契约，后续
调度与用户地址空间容易混用物理地址、直映地址和普通虚拟地址。

## 决策

### PMM

- 物理页大小固定为 4 KiB；M4 只管理 E820 type 1 且物理地址低于 1 GiB 的完整页。
- bitmap 分别记录 E820 管理范围、当前占用状态和由 `page_alloc` 交付的所有权。
  因而保留页、未管理页、重复释放和未对齐/越界地址都不能通过 `page_free`。
- 永久保留物理 `0..1 MiB`，覆盖 BIOS 数据、stage1/stage2、`boot_info`/E820、M2
  页表/切换栈和 VGA；另按 `boot_info` 保留完整 kernel physical range。
- `boot_info v1` 与 E820 entries 必须在 CR3 切换前复制到内核静态存储。
- `page_alloc` 第一版线性扫描 bitmap；耗尽、重复初始化和非法释放都 panic。

### 最终页表与 VMM

- 物理直映窗口固定为 `0xffff800000000000 + physical`，覆盖物理 `0..1 GiB`。
- kernel 保持 `0xffffffff80000000` 起始的 higher-half 映射：text 为 R-X，rodata
  为 R--，data/BSS 为 RW-。CPU 必须支持 NX，并启用 `EFER.NXE` 与 `CR0.WP`。
- 直映别名统一 NX；与 kernel physical range 重叠的 2 MiB 区间拆为 4 KiB PTE，
  text/rodata 别名保持只读。其他直映区使用 2 MiB huge pages。
- M2 低 1 GiB identity map 被替换；最终低地址只保留 VGA `0xb8000` 的 4 KiB
  identity mapping，供当前 console 使用。
- 页表页来自 PMM。`vm_map`、`vm_unmap`、`vm_protect`、`vm_translate` 统一处理
  4 KiB 映射；改变活动 PTE 后执行 `invlpg`。M4 不回收空的中间页表。
- 内存自测/权限 fault 使用 `0xffffc00000000000`，不与 kernel、直映或 heap 重叠。

### 内核堆

- heap 虚拟区固定为 `0xffffc10000000000..0xffffc10001000000`（最大 16 MiB）。
- heap 按需从 PMM 取页并通过 VMM 建立 RW-/NX 映射；已映射 heap 页不退还 PMM。
- 第一版使用 16-byte 对齐的 boundary-tag first-fit free-list。每块有 24-byte header
  和 8-byte footer；释放时同时向前、向后合并，损坏 tag、越界或重复释放会 panic。

### 验证模式

- `KERNEL_TEST_MODE=0`：PMM 64 页批量压力、VMM map/unmap、7000-byte 跨页 heap
  读写与复用，然后继续 M3 timer/keyboard 路径。
- mode 1 保留 M3 divide error；mode 2/3/4 分别制造 unmapped read、supervisor
  read-only write 和 NX instruction fetch，预期 page-fault error code 为 `0x0/0x3/0x11`。

## 影响

- M5 可以使用 `kmalloc/kfree` 和 `page_alloc/page_free`，无需依赖 M2 低地址映射。
- 1 GiB 是 M4 教学上限，不代表 x86_64 或 E820 上限；扩展到全部 RAM 时需要动态
  PMM metadata、更多直映范围和大物理地址测试。
- 直映包含 1 GiB 范围内的 holes/MMIO，但 PMM 仍只分配 E820 type 1 RAM。
- heap 当前不缩容，中间页表也不回收；长期碎片、并发锁、per-CPU allocator 和
  用户地址空间回收留给后续阶段。
