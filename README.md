# Tiny Linux Kernel

一个从零实现的 x86_64 类 Linux 教学内核，用来学习计算机如何从 BIOS 启动，内核如何管理内存、调度多个任务，以及文件系统如何把磁盘扇区组织成目录和文件。

本项目追求的是“结构清楚、可以观察、可以逐步验证”，不是替代 Linux，也不追求完整 POSIX 兼容。

> **当前状态**
>
> 项目目前处于规划与基础设施阶段：总体路线和多会话交接机制已经建立，M0 构建骨架尚未开始。现在还没有 bootloader、kernel、Makefile 或可启动镜像。准确进度请查看 [PROJECT_STATUS.md](PROJECT_STATUS.md)。

## 最终要实现什么

完成后的系统将具备：

- 项目自带的 BIOS 两阶段 bootloader。
- 从 16 位 real mode 进入 x86_64 long mode。
- 物理页分配、四级页表、虚拟地址空间和内核堆。
- 内核线程、用户进程和时钟中断驱动的抢占式调度。
- Ring 3 用户态、最小系统调用和 ELF64 用户程序加载。
- VFS、内存文件系统 ramfs 和可持久化的 simplefs。
- ATA PIO 虚拟磁盘驱动。
- `/bin/init`、交互式 shell 和基础用户程序。
- QEMU 串口日志、GDB remote 调试和自动化冒烟测试。

这里的“类 Linux”指采用 Linux/Unix 风格的进程、文件描述符、系统调用和 VFS 模型，不表示兼容 Linux ABI，也不能直接运行现成 Linux 程序。

## 系统全景

```text
宿主 Linux / WSL
└── QEMU 虚拟电脑
    ├── BIOS
    │   └── stage1 -> stage2
    ├── x86_64 CPU + RAM
    │   └── kernel
    │       ├── 中断和设备驱动
    │       ├── PMM / VMM / heap
    │       ├── scheduler / processes
    │       ├── syscalls / VFS
    │       └── ramfs / simplefs
    └── IDE 虚拟磁盘
        └── boot image + persistent data
```

预期启动链路：

```text
BIOS
  -> 512-byte stage1
  -> stage2 + E820 + ELF64 loader
  -> x86_64 higher-half kernel
  -> memory + interrupts + scheduler
  -> VFS + disk filesystem
  -> Ring 3 /bin/init
  -> /bin/sh
```

## QEMU 在这里做什么

QEMU 是一台由软件模拟出来的电脑。它为 toy kernel 提供可重复的虚拟硬件：

- BIOS：读取 boot sector 并开始启动。
- x86_64 CPU：执行 bootloader 和内核指令。
- RAM：用于学习物理内存和虚拟内存管理。
- IDE 硬盘：用于练习 ATA 驱动和持久化文件系统。
- PIT、PIC、键盘、VGA 和串口：用于中断、输入输出和任务调度。

内核崩溃时只会影响虚拟机，不会让宿主系统崩溃。QEMU 还可以暂停虚拟 CPU，并通过 GDB 检查寄存器、内存和汇编执行过程。

QEMU 不是内核的一部分：

```text
QEMU 提供虚拟硬件 -> bootloader 启动 -> kernel 管理硬件
```

当前机器已经有一个可用的 QEMU 11.0.2 本地构建，但它不在 `PATH`：

```text
/home/godot/ai_native/QEMU_NET/qemu-build/qemu-system-x86_64
/home/godot/ai_native/QEMU_NET/qemu-build/qemu-img
```

后续 Makefile 会支持通过 `QEMU` 和 `QEMU_IMG` 变量覆盖路径，而不是要求每台机器都使用上述绝对路径。

## 技术选择

| 项目 | 选择 |
|---|---|
| 目标平台 | 单核 x86_64，QEMU `pc` |
| 启动 | Legacy BIOS，自制 MBR stage1 + stage2 |
| 语言 | freestanding C11 + GNU assembler (`.S`) |
| 构建 | Make、GCC/Clang、GNU binutils |
| 内核布局 | ELF64 higher-half kernel |
| 内存 | 4 KiB 页、bitmap PMM、四级页表 |
| 调度 | PIT 驱动的抢占式 round-robin |
| 文件系统 | VFS + ramfs + 自定义 simplefs |
| 磁盘 | QEMU IDE + ATA PIO |
| 调试 | 串口、QEMU debug 日志、GDB remote |

重要设计选择及原因记录在 [DECISIONS.md](DECISIONS.md)。

## 实现路线

| 里程碑 | 内容 | 当前状态 |
|---|---|---|
| M0 | 工程骨架、工具检测、可重复构建 | 未开始 |
| M1 | 512 字节 stage1 | 未开始 |
| M2 | stage2、E820、ELF loader、long mode | 未开始 |
| M3 | console、中断、PIC/PIT、键盘 | 未开始 |
| M4 | PMM、VMM、最终页表、内核堆 | 未开始 |
| M5 | 内核线程和抢占式调度 | 未开始 |
| M6 | Ring 3、进程和系统调用 | 未开始 |
| M7 | VFS 和 ramfs | 未开始 |
| M8 | ATA PIO 和持久化 simplefs | 未开始 |
| M9 | init、shell、用户程序和集成测试 | 未开始 |
| M10 | 稳定性、压力测试和文档收尾 | 未开始 |

完整任务、验收条件和风险分析见 [plan.md](plan.md)，实时任务状态见 [TASKS.md](TASKS.md)。

## 构建与运行

当前尚未进入 M0，因此下面是计划中的最终使用方式，**现在还不能执行成功**：

```sh
make doctor
make image
make run
```

预期含义：

- `make doctor`：检查编译器、binutils、QEMU 和可选 GDB。
- `make image`：编译 bootloader、kernel 和用户程序，生成磁盘镜像。
- `make run`：在 QEMU 中从磁盘镜像启动。
- `make debug`：让 QEMU 暂停在启动位置并开放 GDB remote。
- `make test`：通过串口运行启动与功能冒烟测试。

已经确认可用的宿主工具：

```text
make
gcc
clang
ld
QEMU 11.0.2（使用上面的本地路径）
```

GDB 当前尚未在 `PATH` 中检测到。工具探测和跨机器配置将在 M0 实现。

## 当前目录导航

```text
.
├── AGENTS.md              # Codex 多会话协作规则
├── README.md              # 项目入口
├── plan.md                # M0-M10 总体实施计划
├── PROJECT_STATUS.md      # 当前已经实现和验证的事实
├── TASKS.md               # 任务状态与依赖
├── DECISIONS.md           # 架构决策索引
├── docs/
│   ├── claims/            # 活动/已关闭的写入范围 claim
│   ├── decisions/         # 完整架构决策
│   └── sessions/          # 每次写会话的操作和结果
└── tools/
    ├── project-context.sh
    └── check-project-state.sh
```

`boot/`、`kernel/`、`user/` 和 `tests/` 会在对应里程碑开始时逐步建立，不预先创建空目录。

## 多会话开发

项目不依赖聊天历史保存进度。新的 Codex 会话进入目录后，应执行：

```sh
./tools/project-context.sh
./tools/check-project-state.sh
```

工作流程：

```text
读取状态
  -> 创建 session log 和 active claim
  -> 修改与测试
  -> 记录实际结果
  -> 更新 TASKS / PROJECT_STATUS
  -> claim 移入 closed
  -> 一致性检查
```

每个写会话通过 `docs/claims/active/` 声明负责的最小文件范围。检查器会拒绝类似 `kernel/` 与 `kernel/mm/` 的重叠 claim，从而降低并行会话互相覆盖的风险。完整规则见 [AGENTS.md](AGENTS.md)。

如果一个会话意外中断，下一个会话会保留已有文件，读取残留 claim 和 session log，再使用新的 session ID 继续；不会默认删除未完成改动。

## 学习建议

建议严格按 M0 → M10 推进，并在每个阶段回答三个问题：

1. CPU 或设备此时处于什么状态？
2. 内核依赖哪些不变量才能继续执行？
3. 怎样通过串口、异常信息或测试证明它真的工作？

早期最重要的不是快速堆功能，而是保证每一个启动阶段都有输出、每一种失败都能定位、每个里程碑都保持可构建和可验证。

## 项目边界

第一版不包含：

- SMP 和多核调度。
- UEFI、Secure Boot 和真实硬件兼容。
- 网络、USB、图形界面和音频。
- 动态链接和共享库。
- 完整 POSIX、权限安全模型。
- journaling 和崩溃恢复。

这些内容可以作为核心目标完成后的扩展练习。

