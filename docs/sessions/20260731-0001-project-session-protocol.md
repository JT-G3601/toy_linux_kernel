# Session `20260731-0001-project-session-protocol`

## 元数据

- 任务：`TASK-INFRA-001`
- 日期：2026-07-31
- Base revision：unversioned
- Claim：`docs/claims/closed/20260731-0001-project-session-protocol.md`
- Continues：none

## 接手状态

- 项目只有 `plan.md`。
- 尚未初始化 Git 仓库。
- QEMU 11.0.2 是 `QEMU_NET` 项目内的本地构建，不在当前 PATH。

## 目标

- 让后续 Codex 会话无需依赖聊天历史即可恢复项目上下文。
- 让顺序和并发会话能够区分当前事实、历史操作和写入所有权。

## 实际修改

- 增加根目录 `AGENTS.md` 会话启动、claim、收尾和中断恢复规则。
- 增加项目状态、任务注册表和决策索引。
- 增加独立 session log、active/closed claim 结构和模板。
- 增加快速简报与一致性检查脚本。
- 更正 `plan.md` 对 QEMU 可用性的描述。

## 验证

| 命令/检查 | 结果 | 关键输出或说明 |
|---|---|---|
| `tools/project-context.sh` | `PASS` | 正确显示状态、任务、决策、active claim 和最近日志 |
| `tools/check-project-state.sh` | `PASS` | 项目状态自检通过，0 个 active claim |
| 临时 fixture 中 claim `kernel/` 与 `kernel/mm/` | `PASS` | 检查器返回 FAIL 并准确报告父子 scope 冲突 |
| `bash -n tools/*.sh` | `PASS` | 两个辅助脚本语法检查通过 |
| QEMU `--version` | `PASS` | QEMU 11.0.2 |
| QEMU `-machine help` | `PASS` | 能列出 x86 PC machine |

## 未完成与风险

- 项目没有 Git revision，暂时只能将 base 标为 `unversioned`。
- 该协议是协作约定，不是操作系统级强制文件锁。

## 交接建议

- 下一会话从 `TASK-M0-001` 开始。
- Makefile 应支持显式 `QEMU`/`QEMU_IMG`，并可探测已知的本地 QEMU build。
