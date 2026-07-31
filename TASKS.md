# Task Registry

任务状态的允许值见 `AGENTS.md`。任务进入 `in_progress` 时，必须能在
`docs/claims/active/` 找到对应 claim；进入 `done` 时必须在会话日志中记录验证证据。

| ID | 状态 | 里程碑 | 内容 | 依赖 | 最近会话 |
|---|---|---|---|---|---|
| `TASK-PLAN-001` | `done` | 规划 | 编写总体实现计划 | 无 | `20260731-0000-initial-plan` |
| `TASK-INFRA-001` | `done` | 项目基础设施 | 建立多会话状态、claim、日志和检查协议 | `TASK-PLAN-001` | `20260731-0001-project-session-protocol` |
| `TASK-DOC-001` | `done` | 项目文档 | 编写根目录 README | `TASK-INFRA-001` | `20260731-1435-project-readme` |
| `TASK-PUBLISH-001` | `done` | 项目发布 | 初始化 Git 并发布公开 GitHub 仓库 | `TASK-DOC-001` | `20260731-1451-github-initial-publish` |
| `TASK-M0-001` | `done` | M0 | Makefile、链接骨架、工具检测、镜像与运行入口 | `TASK-INFRA-001` | `20260731-1506-m0-build-foundation` |
| `TASK-M1-001` | `todo` | M1 | 512 字节 stage1 bootloader | `TASK-M0-001` | - |
| `TASK-M2-001` | `todo` | M2 | stage2、E820、ELF64 loader、long mode | `TASK-M1-001` | - |
| `TASK-M3-001` | `todo` | M3 | console、GDT/IDT/TSS、异常、PIC/PIT、键盘 | `TASK-M2-001` | - |
| `TASK-M4-001` | `todo` | M4 | PMM、VMM、最终页表与内核堆 | `TASK-M3-001` | - |
| `TASK-M5-001` | `todo` | M5 | 内核线程与抢占式调度 | `TASK-M4-001` | - |
| `TASK-M6-001` | `todo` | M6 | Ring 3、进程、ELF 用户程序与系统调用 | `TASK-M5-001` | - |
| `TASK-M7-001` | `todo` | M7 | VFS 与 ramfs | `TASK-M6-001` | - |
| `TASK-M8-001` | `todo` | M8 | ATA PIO 与持久化 simplefs | `TASK-M7-001` | - |
| `TASK-M9-001` | `todo` | M9 | init、shell、用户程序与集成测试 | `TASK-M8-001` | - |
| `TASK-M10-001` | `todo` | M10 | 稳定性、压力测试和文档收尾 | `TASK-M9-001` | - |

## 任务维护规则

- 不因“写过一些代码”就改为 `done`；必须满足对应里程碑的验收条件。
- 若任务过大，在开始前拆为稳定 ID 的子任务，例如 `TASK-M4-002`。
- 删除任务会破坏会话引用；不再需要的任务标记 `superseded` 并说明替代项。
- 会话日志记录细节，本表只保存当前状态和最新关联会话。
