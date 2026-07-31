# Project Status

> 这是项目当前状态的权威摘要，只记录可以由文件或验证命令支持的事实。

## 状态元数据

- 最后更新：2026-07-31
- 更新会话：`20260731-1435-project-readme`
- 当前阶段：规划与项目基础设施
- 当前里程碑：M0 尚未开始
- 项目版本：尚未初始化 Git 仓库

## 已完成

- 已制定 x86_64 toy kernel 的总体实现计划与 M0-M10 验收标准。
- 已创建面向学习者的根目录 README，说明项目目标、QEMU、架构路线、当前状态和开发入口。
- 已建立项目原生的多会话交接协议：
  - 根目录 `AGENTS.md` 自动向新 Codex 会话提供协作规则。
  - `PROJECT_STATUS.md` 保存最新事实。
  - `TASKS.md` 保存任务状态。
  - `docs/sessions/` 保存独立、可追溯的会话日志。
  - `docs/claims/` 用最小写入范围协调并发会话。
  - `docs/decisions/` 保存架构决策。
  - `tools/project-context.sh` 生成快速项目简报。
  - `tools/check-project-state.sh` 检查状态文件和 claim 冲突。

## 尚未实现

- bootloader、内核、用户态、文件系统以及构建系统均尚未开始。
- 当前还没有可启动的磁盘镜像。
- 当前还没有自动化内核测试。

## 已验证的开发环境

| 能力 | 结果 | 证据 |
|---|---|---|
| GNU Make | 可用 | `/usr/bin/make` |
| GCC | 可用 | `/usr/bin/gcc` |
| Clang | 可用 | `/usr/bin/clang` |
| GNU ld | 可用 | `/usr/bin/ld` |
| QEMU x86_64 | 可用但不在 `PATH` | `/home/godot/ai_native/QEMU_NET/qemu-build/qemu-system-x86_64 --version` 返回 QEMU 11.0.2 |
| qemu-img | 可用但不在 `PATH` | `/home/godot/ai_native/QEMU_NET/qemu-build/qemu-img` |
| GDB | `NOT_RUN` | 当前 `PATH` 中未检测到 `gdb` |

## 当前已知限制

- QEMU 是另一个项目的本地 debug build；本项目的构建系统需要允许通过 `QEMU` 和 `QEMU_IMG` 变量覆盖路径。
- 项目尚未初始化 Git，因此暂时没有 commit/branch 可作为会话基线。
- 尚未验证宿主 GCC 的 freestanding x86_64 链接参数和 QEMU BIOS 搜索路径。

## 下一步

执行 `TASK-M0-001`：建立最小构建骨架、工具检测和 QEMU 启动入口。完成标准以 `plan.md` 的 M0 为准。

## 最近验证

| 日期 | 会话 | 检查 | 结果 |
|---|---|---|---|
| 2026-07-31 | `20260731-0001-project-session-protocol` | 本地 QEMU `--version` | `PASS`，QEMU 11.0.2 |
| 2026-07-31 | `20260731-0001-project-session-protocol` | 本地 QEMU `-machine help` | `PASS` |
| 2026-07-31 | `20260731-0001-project-session-protocol` | 多会话状态检查脚本 | `PASS`，0 个 active claim |
| 2026-07-31 | `20260731-0001-project-session-protocol` | 父子 scope 冲突测试 | `PASS`，正确拒绝 `kernel/` 与 `kernel/mm/` |
| 2026-07-31 | `20260731-1435-project-readme` | README 结构与项目内链接 | `PASS`，5 个链接目标均存在 |
