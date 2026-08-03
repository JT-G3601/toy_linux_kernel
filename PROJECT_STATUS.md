# Project Status

> 这是项目当前状态的权威摘要，只记录可以由文件或验证命令支持的事实。

## 状态元数据

- 最后更新：2026-08-03
- 更新会话：`20260803-1721-publish-m1`
- 当前阶段：M1 Legacy BIOS stage1 完成
- 当前里程碑：M1 `done`；下一里程碑 M2
- 项目版本：Git `agent/m0-build`，跟踪 `origin/agent/m0-build`；M1 实现提交 `7748e62`
- GitHub：`https://github.com/JT-G3601/toy_linux_kernel`（public）
- Draft PR：`https://github.com/JT-G3601/toy_linux_kernel/pull/1`（`agent/m0-build` -> `main`）

## 已完成

- 已制定 x86_64 toy kernel 的总体实现计划与 M0-M10 验收标准。
- 已创建面向学习者的根目录 README，说明项目目标、QEMU、架构路线、当前状态和开发入口。
- 已初始化 Git，并将项目发布到公开 GitHub 仓库。
- 已完成 M0 freestanding 构建基础：
  - GCC/Clang 均可构建静态 x86_64 higher-half kernel ELF。
  - 内核入口为 `0xffffffff80000000`，首个 segment LMA 为 1 MiB。
  - 可重复生成并验证 16 MiB `build/toy-linux.img`。
  - kernel ELF 固定存放在镜像 LBA 128。
  - `make doctor/image/verify/run/debug/clean` 已可用。
- 已完成 M1 Legacy BIOS stage1：
  - stage1 严格为 512 字节，带有 `0xAA55` boot signature。
  - 已初始化实模式段寄存器与栈，并保存 BIOS boot drive。
  - 已用 INT 13h extensions 从 LBA 1..127 读取 stage2 到物理地址
    `0x8000`，具备三次重试与 disk reset。
  - stage1 在 VGA 与 COM1 输出 `S1`/`E1`/`E2`，校验 `S2OK` 头后才跳转。
  - M1 最小 stage2 占位程序会输出 `S2` 后停机。
  - `make test-boot` 已验证正常 `S1 -> S2` 与损坏交接头时
    `S1 -> E2` 且不跳转的路径。
  - linker 学习型注释与 M1 实现已分别提交并推送到远程分支，已创建
    面向 `main` 的 draft PR #1。
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

- stage2 目前只是 M1 交接占位程序，尚未实现 E820、ELF64 loader、页表或
  long mode；当前启动链不会进入 kernel `_start`。
- console、中断、内存管理、调度等实际内核子系统尚未实现。
- 用户态、系统调用、VFS 和持久化文件系统尚未实现。
- 已有 stage1/stage2 交接的 QEMU 启动测试，但还没有内核功能测试。

## 已验证的开发环境

| 能力 | 结果 | 证据 |
|---|---|---|
| GNU Make | 可用 | `/usr/bin/make` |
| GCC | 可用 | `/usr/bin/gcc` |
| Clang | 可用 | `/usr/bin/clang` |
| GNU ld | 可用 | `/usr/bin/ld` |
| QEMU x86_64 | 可用但不在 `PATH` | `/home/godot/ai_native/QEMU_NET/qemu-build/qemu-system-x86_64 --version` 返回 QEMU 11.0.2 |
| qemu-img | 可用 | `/usr/bin/qemu-img` |
| GDB | 可选缺失 | 当前 `PATH` 中未检测到 `gdb` |

## 当前已知限制

- `qemu-system-x86_64` 是另一个项目的本地 debug build，不在 `PATH`；Makefile
  可以自动探测该路径，也允许用 `QEMU` 覆盖。
- stage2 的 `S2OK` 是交接头校验，不是整个 stage2 的完整性 checksum。
- M1 stage2 占位程序会有意停机；这是 M2 实现前的预期结果。
- QEMU GDB server 已验证，但本机还没有 GDB 客户端。

## 下一步

执行 `TASK-M2-001`：将 M1 stage2 占位程序替换为 E820/ELF64 loader，建立页表并
进入 long mode。继续遵守 `ADR-0003` 和 `ADR-0004`。

## 最近验证

| 日期 | 会话 | 检查 | 结果 |
|---|---|---|---|
| 2026-07-31 | `20260731-0001-project-session-protocol` | 本地 QEMU `--version` | `PASS`，QEMU 11.0.2 |
| 2026-07-31 | `20260731-0001-project-session-protocol` | 本地 QEMU `-machine help` | `PASS` |
| 2026-07-31 | `20260731-0001-project-session-protocol` | 多会话状态检查脚本 | `PASS`，0 个 active claim |
| 2026-07-31 | `20260731-0001-project-session-protocol` | 父子 scope 冲突测试 | `PASS`，正确拒绝 `kernel/` 与 `kernel/mm/` |
| 2026-07-31 | `20260731-1435-project-readme` | README 结构与项目内链接 | `PASS`，5 个链接目标均存在 |
| 2026-07-31 | `20260731-1451-github-initial-publish` | GitHub 首次发布 | `PASS`，public 仓库、默认 `main` |
| 2026-07-31 | `20260731-1506-m0-build-foundation` | GCC/Clang clean build 与 `make verify` | `PASS` |
| 2026-07-31 | `20260731-1506-m0-build-foundation` | 跨绝对路径重复构建 | `PASS`，kernel/image SHA-256 分别一致 |
| 2026-07-31 | `20260731-1506-m0-build-foundation` | QEMU run/debug 入口 | `PASS`，均保持运行至测试超时 |
| 2026-07-31 | `20260731-1535-push-m0-branch` | 推送远程 M0 分支 | `PASS`，本地与远程 ref 一致 |
| 2026-08-03 | `20260803-1657-m1-stage1` | GCC/Clang `make verify` | `PASS`，512-byte stage1、`0xAA55`、`S2OK` 与镜像布局均通过 |
| 2026-08-03 | `20260803-1657-m1-stage1` | GCC/Clang `make test-boot` | `PASS`，正常 `S1 -> S2`；损坏头 `S1 -> E2` 且不跳转 |
| 2026-08-03 | `20260803-1657-m1-stage1` | GCC 独立目录重复构建 | `PASS`，boot/kernel/image 产物逐字节一致 |
| 2026-08-03 | `20260803-1721-publish-m1` | 推送 `agent/m0-build` | `PASS`，本地与远程 M1 ref 均为 `7748e62` |
| 2026-08-03 | `20260803-1721-publish-m1` | Draft PR #1 | `PASS`，open/draft/mergeable，`agent/m0-build` -> `main` |
