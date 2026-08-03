# ADR-0003：早期 kernel ELF 与磁盘镜像布局

- 状态：accepted
- 日期：2026-07-31

## 背景

M0 需要在 stage1/stage2 尚未实现时生成确定性磁盘镜像。M1 和 M2 必须知道各自可使用
的磁盘范围、kernel ELF 在磁盘中的位置，以及 ELF segment 应加载到的物理地址。
磁盘偏移、物理地址和虚拟地址是三个不同概念，若没有提前固定，后续会话容易使用相同
数字表达不同含义。

## 决策

- 原始磁盘镜像固定为 16 MiB。
- LBA 0（byte 0..511）保留给 M1 stage1。
- LBA 1..127 保留给 stage2。
- kernel ELF 从 LBA 128，即 byte 65,536 开始原样存放。
- kernel ELF 的首个 `PT_LOAD` segment 使用物理地址 `0x00100000`。
- 内核虚拟地址从 `0xffffffff80000000` 开始。
- M0 中 boot/stage2 保留区必须全零；M1/M2 分别负责填充。
- 构建与验证工具共享上述常量，改变布局需要显式 supersede 本 ADR。

## 影响

- M1 可以只写 LBA 0 而不移动现有 kernel payload。
- M2 可在保留区内实现 loader，并从固定 LBA 读取 ELF headers。
- stage2 仍须读取 ELF program headers，不能假定整个 ELF 是可直接执行的平坦二进制。
- 16 MiB 是早期开发镜像，不限制未来独立 simplefs 数据盘的容量。
