# Decision Index

此文件是架构决策索引。完整理由保存在 `docs/decisions/`，已经接受的决策不能在普通实现会话中静默改变；需要新建 superseding decision。

| ID | 状态 | 决策 | 文档 |
|---|---|---|---|
| `ADR-0001` | accepted | 使用 x86_64、Legacy BIOS、自制两阶段 bootloader | `docs/decisions/0001-platform-and-boot.md` |
| `ADR-0002` | accepted | 使用项目内权威状态、独立会话日志和 scope claim 支持多会话 | `docs/decisions/0002-session-continuity.md` |
| `ADR-0003` | accepted | 固定早期 kernel ELF 的磁盘位置、LMA 与 higher-half VMA | `docs/decisions/0003-early-kernel-image-layout.md` |
| `ADR-0004` | accepted | 固定 stage1 读取范围、stage2 加载地址与交接头 | `docs/decisions/0004-stage1-stage2-contract.md` |
