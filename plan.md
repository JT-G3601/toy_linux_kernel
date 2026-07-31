# Toy Linux Kernel 实现计划

## 1. 项目目标

在 x86_64/QEMU 上从零实现一个用于学习的类 Linux 教学内核。最终系统应能：

- 由项目自带的 BIOS 两阶段 bootloader 启动，不依赖 GRUB。
- 进入 64 位 long mode，初始化中断、定时器和基础设备。
- 管理物理内存与进程虚拟地址空间。
- 同时运行多个内核任务和用户进程，并由时钟中断抢占调度。
- 提供最小系统调用、用户态和 shell。
- 通过 VFS 使用内存文件系统，并在虚拟 IDE 磁盘上读写持久化文件。
- 在 QEMU 中一条命令构建、制作磁盘镜像并启动。
- 关键模块配有文档和可重复的自测，重点服务于学习与调试。

这里的 “Linux” 表示采用 Linux/Unix 风格的进程、系统调用、VFS 和用户态模型；不追求 Linux ABI、POSIX 完整兼容，也不运行现成 Linux 程序。

## 2. 范围控制

### 本项目包含

- Legacy BIOS 启动。
- 单核 x86_64。
- 自制 stage1/stage2 bootloader。
- ELF64 内核加载。
- 串口、VGA 文本输出和 PS/2 键盘输入。
- GDT、IDT、TSS、PIC、PIT。
- 物理页分配、四级页表、内核堆。
- 内核线程、用户进程、抢占式轮转调度。
- `fork`/`exec` 的教学版实现，或等价的 `spawn` 路径后再补齐。
- 最小 VFS、ramfs 和持久化 simplefs。
- ATA PIO 块设备驱动。
- 最小 shell 和若干用户程序。

### 暂不包含

- SMP、多核调度。
- UEFI、Secure Boot。
- USB、网络、图形界面、音频。
- 动态链接、共享库。
- 完整 POSIX、权限模型或安全加固。
- journaling、崩溃恢复、高性能磁盘缓存。
- 在真实硬件上运行；第一目标始终是 QEMU。

## 3. 技术路线

| 项目 | 选择 |
|---|---|
| 目标平台 | `x86_64`，QEMU `pc` 机器 |
| 启动方式 | Legacy BIOS，自制 MBR stage1 + stage2 |
| 主要语言 | freestanding C11 + GNU assembler (`.S`) |
| 构建 | Makefile、GCC/Clang、GNU binutils |
| 调试 | QEMU 串口、debugcon、GDB remote |
| 内核格式 | ELF64，higher-half 内核 |
| 页大小 | 4 KiB；早期映射可临时使用 2 MiB huge page |
| 调度 | 单 CPU、固定时间片、优先级相同的 round-robin |
| 用户 ABI | 自定义的最小 SysV x86_64 风格 ABI，`syscall` 或 `int 0x80` |
| 文件系统 | VFS + ramfs + 自定义 simplefs |
| 磁盘 | QEMU IDE，ATA PIO，独立数据镜像 |
| 许可证 | 建议 MIT，便于学习和复用 |

优先使用 GNU assembler 而不是 NASM，减少额外工具依赖。内核不链接宿主 libc，也不依赖宿主头文件。

## 4. 预期目录结构

```text
.
├── Makefile
├── README.md
├── plan.md
├── boot/
│   ├── stage1.S
│   ├── stage2.S
│   ├── stage2.c
│   ├── boot.h
│   └── linker.ld
├── kernel/
│   ├── arch/x86_64/
│   │   ├── entry.S
│   │   ├── gdt.c
│   │   ├── idt.c
│   │   ├── isr.S
│   │   ├── paging.c
│   │   ├── context.S
│   │   └── syscall.S
│   ├── mm/
│   │   ├── pmm.c
│   │   ├── vmm.c
│   │   └── heap.c
│   ├── sched/
│   │   ├── task.c
│   │   └── scheduler.c
│   ├── fs/
│   │   ├── vfs.c
│   │   ├── ramfs.c
│   │   └── simplefs.c
│   ├── drivers/
│   │   ├── serial.c
│   │   ├── vga.c
│   │   ├── keyboard.c
│   │   ├── pit.c
│   │   ├── pic.c
│   │   └── ata.c
│   ├── syscall/
│   ├── include/
│   ├── lib/
│   ├── main.c
│   └── linker.ld
├── user/
│   ├── crt0.S
│   ├── libc/
│   ├── init.c
│   ├── sh.c
│   └── programs/
├── tools/
│   ├── mkimage.sh
│   ├── mksimplefs.c
│   └── check_boot.py
├── tests/
└── docs/
    ├── boot.md
    ├── memory.md
    ├── scheduler.md
    └── filesystem.md
```

实际实现时按里程碑逐步创建文件，避免先铺设大量空壳。

## 5. 分阶段实现

### M0：工程骨架和可重复构建

任务：

- 建立 Makefile、链接脚本、公共类型和 freestanding C 编译参数。
- 添加 `make`, `make image`, `make run`, `make debug`, `make clean`。
- 构建时启用 `-ffreestanding -fno-stack-protector -fno-pic -mno-red-zone`。
- 检测必要工具并给出清晰错误；不静默使用宿主 libc。
- 所有镜像和中间文件放入 `build/`。

验收：

- `make image` 从干净目录稳定生成启动镜像。
- 重复构建结果可复现。
- 当前环境已有 `make/gcc/clang/ld`。QEMU 11.0.2 位于
  `/home/godot/ai_native/QEMU_NET/qemu-build/qemu-system-x86_64`，可直接使用但不在
  `PATH`；GDB 尚未检测到，进入源码级调试前需补齐或指定路径。

### M1：stage1 bootloader

任务：

- 编写严格限制为 512 字节的 MBR boot sector。
- 初始化段寄存器和栈，保存 BIOS boot drive。
- 用 BIOS INT 13h extensions 从固定 LBA 加载 stage2。
- 对磁盘读取失败进行重试，并在 VGA/串口输出短错误码。
- 加入 `0xAA55` boot signature 和构建期尺寸断言。

验收：

- QEMU 启动后能看到 stage1/stage2 标识。
- 故意损坏 stage2 时能够报告错误并停机，不跳入未知内存。

### M2：stage2、硬件信息和 long mode

任务：

- 启用 A20。
- 通过 BIOS E820 获取物理内存映射。
- 从磁盘加载 ELF64 内核，解析并校验 program headers。
- 建立临时 GDT 和四级页表。
- 同时建立低地址 identity map 与 higher-half 内核映射。
- 开启 PAE、EFER.LME 和 paging，跳转到 64 位内核入口。
- 用版本化 `boot_info` 结构传递内存图、磁盘号和内核范围。

验收：

- 内核确认自己处于 long mode，并打印 E820 map。
- 内核入口地址由 ELF 决定，而不是写死到 bootloader。
- 非法 ELF 或内存不足时 stage2 给出明确错误。

### M3：内核基础设施和中断

任务：

- 实现 `memcpy/memset/memmove/strlen`、格式化输出和 `panic`。
- 初始化 COM1 串口与 VGA text console，统一到简单 console 接口。
- 创建内核 GDT、IDT、TSS 和异常入口。
- remap 8259 PIC，配置 PIT 周期时钟。
- 实现 page fault、general protection fault 等异常信息和寄存器转储。
- 实现 PS/2 键盘扫描码到字符的基本转换。

验收：

- 定时器 tick 稳定递增，键盘可以回显。
- 人工触发除零和 page fault 时，能打印异常类型、地址和寄存器后停机。

### M4：物理与虚拟内存管理

任务：

- 解析 E820，只管理可用 RAM，保留 BIOS、bootloader、内核和设备区域。
- 实现 4 KiB 页框分配器；第一版使用 bitmap。
- 实现页表 walk/map/unmap、权限位和 TLB 刷新。
- 建立最终 higher-half 内核页表，移除不再需要的低地址映射。
- 实现内核堆；第一版可采用边界标记 free-list。
- 添加页分配统计、重复释放和越界检测。

验收：

- 页框批量分配/释放压力测试后空闲数恢复。
- 跨页堆对象可读写，释放后空间可复用。
- 不可访问页、只读页和 NX 页产生预期 fault。

### M5：内核线程和抢占式调度

任务：

- 定义任务状态、内核栈、保存的寄存器上下文和运行队列。
- 实现创建、阻塞、唤醒、退出、回收和上下文切换。
- 用 PIT tick 驱动固定时间片 round-robin 抢占。
- 提供等待队列和最小自旋锁/关中断临界区规则。
- 实现 idle task，避免无任务时忙乱访问队列。

验收：

- 至少 3 个内核线程持续交错输出各自计数。
- 某线程主动 yield、sleep 或 exit 不会破坏其他线程。
- 运行大量切换后栈和页框计数无持续泄漏。

### M6：用户态、进程和系统调用

任务：

- 创建独立用户页表、用户栈和 Ring 3 入口。
- 配置 TSS `rsp0`，保证用户态陷入时切到内核栈。
- 实现系统调用入口、参数校验和用户指针复制。
- 第一组系统调用：`write`, `read`, `open`, `close`, `exit`, `yield`, `sleep`, `getpid`, `sbrk`。
- 加入 ELF64 用户程序加载器。
- 先实现 `spawn`/`exec`，稳定后增加教学版 `fork`、`wait`。
- 每个进程拥有 fd table、地址空间和生命周期状态。

验收：

- 两个互不信任的 Ring 3 程序被抢占运行。
- 一个程序访问内核地址时只终止该进程，内核继续运行。
- 用户指针非法时系统调用返回错误，不导致 kernel panic。

### M7：VFS 和 ramfs

任务：

- 定义 inode/dentry/file/file_operations 的精简接口。
- 实现绝对/相对路径解析、`.`、`..` 和 mount point。
- 实现 ramfs 的目录、普通文件、创建、读写、截断和删除。
- 将 console 暴露为 `/dev/console`。
- 将进程 fd table 接入 VFS，并补齐 `stat`, `mkdir`, `unlink`, `readdir`, `chdir`。

验收：

- 用户程序可创建目录和文件，写入后重新打开并读回。
- 多个 fd 的 offset 相互独立。
- shell 可执行 `ls`, `cat`, `echo`, `mkdir`, `cd`, `rm`。

### M8：ATA PIO 和持久化 simplefs

任务：

- 实现 QEMU IDE primary bus 的 ATA PIO LBA28 扇区读写。
- 提供统一 block device API 和小型块缓存。
- 定义 simplefs 磁盘格式：superblock、inode bitmap、block bitmap、inode table、data blocks、定长或变长目录项。
- 提供宿主侧 `mksimplefs`，将用户程序和初始文件打包进数据镜像。
- 实现挂载、格式化、文件/目录创建、跨块读写、删除和空间回收。
- 关键元数据写入顺序尽量避免明显的半写状态，但不实现 journal。

验收：

- 在 shell 中创建文件、关机、重启后内容仍存在。
- 大于一个 block 的文件能够正确读写。
- 删除文件后 inode 和数据块可重新分配。
- 坏 superblock 被拒绝挂载，不破坏磁盘。

### M9：init、shell 和学习体验

任务：

- 启动第一个用户进程 `/bin/init`，再启动 `/bin/sh`。
- shell 支持命令、参数、当前目录和基础内建命令。
- 提供 `hello`, `memtest`, `ps`, `ls`, `cat`, `echo`, `mkdir`, `rm` 等程序。
- README 说明依赖、构建、运行、调试和常见故障。
- 为 boot、内存、调度、系统调用、文件系统分别写数据流说明。
- 在关键结构和汇编边界解释“为什么”，而不只解释“做了什么”。

验收：

- 从 BIOS 启动到 shell 无人工干预。
- `ps` 能观察多个任务；文件命令可操作 ramfs 和磁盘 simplefs。
- `make test` 能运行串口驱动的启动/功能冒烟测试。

### M10：稳定性和收尾

任务：

- 开启 `-Wall -Wextra -Werror`，清理未定义行为和隐式转换。
- 添加内核断言、对象魔数、栈哨兵和内存统计命令。
- 做长时间调度、页分配、文件创建/删除压力测试。
- 固定磁盘格式版本和 boot protocol 版本。
- 记录已知限制和下一步练习方向。

验收：

- QEMU 中连续运行压力测试，无 panic、死锁或单调内存泄漏。
- 从全新 clone 到 shell 的操作能完全按 README 复现。

## 6. 每个阶段的完成规则

一个里程碑只有同时满足以下条件才算完成：

1. 功能代码已实现，不以硬编码输出代替真实行为。
2. 能从干净的 `build/` 目录重新构建。
3. 有正常路径和至少一个错误路径测试。
4. 串口日志足以定位失败阶段。
5. 对外结构、关键不变量和限制已写入文档。
6. 前一阶段的冒烟测试仍通过。

## 7. 关键接口约定

实现前优先固定以下接口，减少模块互相渗透：

- `boot_info`：只由 bootloader 写、内核读，带 magic/version/size。
- `page_alloc/page_free`：物理页分配器不直接依赖堆。
- `vm_map/vm_unmap`：所有地址空间映射走统一 API。
- `task_block/task_wake`：驱动和文件系统不直接操作 run queue。
- `copy_from_user/copy_to_user`：系统调用不直接解引用用户指针。
- `block_read/block_write`：simplefs 不直接操作 ATA 端口。
- `vfs_*`：系统调用不依赖具体 ramfs/simplefs 结构。

## 8. 测试策略

### 构建期检查

- boot sector 恰好 512 字节且末尾签名正确。
- ELF segment 不重叠，入口位于可执行 segment。
- C 结构磁盘布局使用静态断言。
- freestanding 目标不存在未预期的 libc 符号。

### 内核自测

- bitmap 页分配器随机序列测试。
- 页表映射/解除映射测试。
- run queue 状态转换测试。
- 路径规范化和目录查找测试。
- simplefs block/inode 分配与回收测试。

### QEMU 集成测试

- 串口等待 `kernel: ready`、`user: ready`、`shell: ready` 标记。
- 向 QEMU 输入命令并匹配输出。
- 重启虚拟机验证磁盘文件持久化。
- 为 panic 设置超时，避免 CI 永久挂起。

## 9. 主要风险与应对

- **bootloader 调试困难**：每个切换点写串口/debugcon 标记；先加载扁平内核，再升级为 ELF loader。
- **页表错误导致三重故障**：保留最小 identity map；逐项校验页表；QEMU 开启中断/重置日志。
- **抢占引入竞态**：先完成协作式切换，再启用 PIT 抢占；明确哪些函数要求关中断。
- **用户指针拖垮内核**：所有 syscall 使用 copy helper；page fault 区分 user/kernel 来源。
- **文件系统范围膨胀**：只实现单设备、无 journal、有限文件名；VFS 接口保留扩展空间。
- **宿主工具路径不统一**：Makefile 提供 `make doctor`，并允许用 `QEMU`、`QEMU_IMG`
  和 `GDB` 覆盖工具路径；当前 QEMU 可用但不在 `PATH`，GDB 尚未检测到。

## 10. 最终验收场景

执行：

```sh
make clean
make image
make run
```

系统应经历以下链路：

```text
BIOS
  -> stage1
  -> stage2 + E820 + ELF loader
  -> x86_64 higher-half kernel
  -> PMM/VMM/heap
  -> interrupts + preemptive scheduler
  -> VFS + ramfs + ATA + simplefs
  -> Ring 3 /bin/init
  -> interactive /bin/sh
```

在 shell 中至少能完成：

```text
ps
mkdir /disk/demo
echo hello > /disk/demo/message
cat /disk/demo/message
memtest
```

重启后 `/disk/demo/message` 仍能读出 `hello`，同时 `ps` 显示多个可调度任务，即视为核心目标完成。

## 11. 推荐实施顺序

严格按 M0 → M10 推进，每个里程碑保持可启动、可观察。前四个里程碑先建立可靠的启动和调试底座；随后完成内存与调度；最后接用户态和文件系统。实现中如果需要临时简化，允许使用 ramfs 作为根文件系统、simplefs 挂载到 `/disk`，但不跳过模块边界和验收测试。
