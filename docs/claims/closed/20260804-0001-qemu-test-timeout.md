---
session_id: 20260804-0001-qemu-test-timeout
task_ids: TASK-TEST-001
owner: codex
started_at: 2026-08-04T00:01:40+08:00
base_revision: 5780abb
status: completed
continues: 20260803-2311-textbook-docs
scope:
  - Makefile
  - tools/test-boot.sh
  - docs/build.md
  - docs/textbook/m2-loader-long-mode.md
  - README.md
  - TASKS.md
  - PROJECT_STATUS.md
  - docs/sessions/20260804-0001-qemu-test-timeout.md
  - docs/claims/active/20260804-0001-qemu-test-timeout.md
  - docs/claims/closed/20260804-0001-qemu-test-timeout.md
---

# Claim 说明

修复 QEMU debug build 冷启动超过硬编码 2 秒导致的启动测试误报：让超时可由
Make 变量配置、提高默认值，并在断言失败时输出捕获到的 QEMU 日志。同步说明
当前 Guest `HLT` 后由测试 harness 超时终止 QEMU 的完成语义。
