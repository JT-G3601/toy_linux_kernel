---
session_id: 20260804-0011-qemu-marker-wait
task_ids: TASK-TEST-002
owner: codex
started_at: 2026-08-04T00:11:06+08:00
base_revision: 5780abb
status: completed
continues: 20260804-0001-qemu-test-timeout
scope:
  - Makefile
  - tools/test-boot.sh
  - docs/build.md
  - docs/textbook/m2-loader-long-mode.md
  - README.md
  - TASKS.md
  - PROJECT_STATUS.md
  - docs/sessions/20260804-0011-qemu-marker-wait.md
  - docs/claims/active/20260804-0011-qemu-marker-wait.md
  - docs/claims/closed/20260804-0011-qemu-marker-wait.md
---

# Claim 说明

根据用户交互式 WSL 中 5 秒仍无 captured stdout 的证据，将 QEMU 测试从“固定
等待后读取 command substitution”改为“串口文件 + 终止标记轮询 + 主动回收”。
超时只作为最大上限，从而消除 TTY/pipe 差异并让成功测试及时完成。
