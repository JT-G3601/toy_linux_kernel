---
session_id: 20260804-0029-kernel-boot-guide
task_ids: TASK-DOC-003
owner: codex
started_at: 2026-08-04T00:29:04+08:00
closed_at: 2026-08-04T00:35:54+08:00
base_revision: 5780abb
status: completed
continues: 20260804-0011-qemu-marker-wait
scope:
  - docs/textbook/kernel-boot-deep-dive.md
  - docs/textbook/README.md
  - docs/textbook/m2-loader-long-mode.md
  - README.md
  - TASKS.md
  - PROJECT_STATUS.md
  - docs/sessions/20260804-0029-kernel-boot-guide.md
  - docs/claims/active/20260804-0029-kernel-boot-guide.md
  - docs/claims/closed/20260804-0029-kernel-boot-guide.md
---

# Claim 说明

根据学习反馈新增一篇独立的 x86_64 内核启动深度教程，从 Legacy BIOS、实模式
寄存器、GDT selector/descriptor、模式切换、ELF 装载、页表到 `kernel_main`
逐步解释，并对比 UEFI、AArch64 和 RISC-V 的启动差异。只修改教材与状态文档。
