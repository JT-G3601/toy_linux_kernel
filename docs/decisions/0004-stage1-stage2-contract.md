# ADR-0004：stage1 与 stage2 交接契约

- 状态：accepted
- 日期：2026-08-03

## 背景

ADR-0003 已把 LBA 1..127 保留给 stage2，但 M1 还需要固定 stage1 如何读取这个
区域、放到哪段实模式内存、怎样拒绝明显无效的 stage2，以及 M2 应从什么
状态继续。

## 决策

- BIOS 在物理地址 `0x7c00` 运行 stage1；stage1 将段寄存器规范化后在
  `0000:7c00` 下方使用栈，并保存 BIOS 传入 `DL` 的 boot drive。
- stage1 要求 BIOS INT 13h extensions，使用 `AH=42h` 和 16-byte disk address
  packet 读取 LBA 1..127。
- 127 个扇区被一次性读取到 `0800:0000`，即物理地址 `0x8000`。从偏移
  0 开始可令 65,024-byte 传输保持在同一 64 KiB 段偏移窗口内。
- 磁盘扩展检查或连续三次读取失败时，stage1 输出 `E1` 并停机。每次失败后
  先执行 BIOS disk reset 再重试。
- stage2 的前 4 字节固定为 ASCII `S2OK`；stage1 检查失败时输出 `E2`
  并停机，成功时保持 boot drive 在 `DL`，跳转至 `0800:0004`。
- stage1 的 `S1`/`E1`/`E2` 同时输出到 BIOS VGA teletype 和 COM1。M1 的最小
  stage2 占位程序输出 `S2` 后停机。

## 影响

- M1 可在不实现 ELF loader 的情况下证明 BIOS -> stage1 -> stage2 交接。
- M2 stage2 可使用最多 65,024 字节，并应保留 `S2OK` 头和 `0800:0004`
  入口，除非用新 ADR 替代本契约。
- `S2OK` 是交接头校验，不是完整性 checksum。M1 的负路径测试会损坏该头，
  确认 stage1 报告 `E2` 且不跳转。
