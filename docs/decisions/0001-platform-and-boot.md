# ADR-0001：目标平台与启动路线

- 状态：accepted
- 日期：2026-07-31

## 背景

项目用于学习操作系统，需要覆盖 bootloader、内存管理、多任务和文件系统，同时要把第一版范围控制在单人可理解和可调试的规模。

## 决策

- 目标为 QEMU `pc` 机器上的单核 x86_64。
- 第一版采用 Legacy BIOS。
- 项目实现自己的 MBR stage1 和 stage2，不依赖 GRUB。
- stage2 获取 E820、加载 ELF64 内核、建立临时页表并进入 long mode。
- 内核主体使用 freestanding C11 和 GNU assembler。

## 影响

- 能完整学习从 real mode 到 long mode 的启动链路。
- 暂不覆盖 UEFI 和真实硬件差异。
- bootloader 的体积、磁盘读取和三重故障调试会成为早期主要风险。

