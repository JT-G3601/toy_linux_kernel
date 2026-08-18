# ADR-0005：M2 loader 低内存布局与 `boot_info v1`

- 状态：accepted
- 日期：2026-08-03

## 背景

M2 必须在 1 MiB 以下同时放置 stage1/stage2、E820 结果、kernel ELF 暂存副本、
页表和切换栈，同时把 ELF segments 加载到 1 MiB 及以上。这些区域若没有固定
契约，BIOS 读盘、页表构建和 ELF 复制容易相互覆盖。内核也需要一个版本化
结构接收 E820、boot drive 和实际 ELF 加载范围。

## 决策

M2 使用以下物理内存布局：

| 物理范围 | 用途 |
|---|---|
| `0x00007c00...` | BIOS stage1 和早期实模式栈 |
| `0x00008000..0x00017dff` | stage2 最大 127 扇区加载区 |
| `0x00018000..0x0001803f` | 64-byte `boot_info v1` |
| `0x00018100..0x000186ff` | 最多 64 个 24-byte E820 entry |
| `0x00020000..0x0005ffff` | kernel ELF 暂存区，最大 256 KiB |
| `0x00060000..0x00084fff` | M2 四级页表 |
| `0x0008f000` 向下 | protected/long-mode 切换栈 |
| `0x00100000...` | ELF `PT_LOAD` segments 的实际 `p_paddr` |

- stage2 从 LBA 128 读取构建时计算的 kernel ELF 扇区数，分批放入暂存区。
- ELF loader 验证 ELF64 little-endian x86_64 executable、header/program-header 边界、
  `PT_LOAD` 的文件/内存大小、higher-half VMA、低于 64 MiB 的物理加载范围，
  以及入口确实落在可执行 `PT_LOAD` 内。
- 复制 segments 之前，loader 要求一个 E820 type 1 entry 完整覆盖实际
  `kernel_phys_start..kernel_phys_end`。
- 临时页表用 2 MiB 大页 identity-map 低 1 GiB，以保持 stage2、`boot_info`、
  E820 和页表可访问。
- higher-half 使用 4 KiB 页，将 `0xffffffff80000000..0xffffffff83ffffff`
  映射到物理 `0x00100000..0x040fffff`，精确保持 ADR-0003 的 1 MiB LMA。
- M2 临时页表为启动映射统一设置 present/writable；M4 建立最终页表时再按
  ELF flags 收紧权限并移除不必要的 identity map。

`boot_info v1` 为 64-byte packed 结构，并通过 System V AMD64 ABI 的 `RDI` 传入
ELF `e_entry`：

| 偏移 | 类型 | 字段 |
|---:|---|---|
| 0 | `u32` | `version = 1` |
| 4 | `u32` | `size = 64` |
| 8 | `u32` | BIOS `boot_drive` |
| 12 | `u32` | `e820_count` |
| 16 | `u64` | `e820_entries` 物理/identity pointer |
| 24 | `u64` | `kernel_phys_start` |
| 32 | `u64` | `kernel_phys_end` |
| 40 | `u64` | `kernel_virt_start` |
| 48 | `u64` | `kernel_virt_end` |
| 56 | `u64` | ELF `kernel_entry` |

E820 entry 使用 BIOS 24-byte 布局：`base u64`、`length u64`、`type u32`、
`attributes u32`。

## 影响

- 早期 kernel ELF 文件大小不得超过 256 KiB；这是 M2 低内存暂存策略的限制，
  不是最终内核大小限制。
- 内核初期可以通过 identity pointer 读取 `boot_info`/E820；M4 移除低映射前
  必须复制数据或建立正式 higher-half 映射。
- M2 可动态跳转 ELF `e_entry`，不把 `0xffffffff80000000` 当作 bootloader
  的控制流常量。
