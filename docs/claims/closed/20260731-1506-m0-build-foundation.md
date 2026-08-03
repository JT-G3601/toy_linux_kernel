---
session_id: 20260731-1506-m0-build-foundation
task_ids: TASK-M0-001
owner: codex
started_at: 2026-07-31T15:06:07+08:00
base_revision: c3cada5
status: completed
continues: none
scope:
  - Makefile
  - kernel/
  - tools/doctor.sh
  - tools/mkimage.sh
  - tools/verify-image.sh
  - docs/build.md
  - DECISIONS.md
  - docs/decisions/0003-early-kernel-image-layout.md
  - README.md
  - TASKS.md
  - PROJECT_STATUS.md
  - docs/sessions/20260731-1506-m0-build-foundation.md
  - docs/claims/active/20260731-1506-m0-build-foundation.md
  - docs/claims/closed/20260731-1506-m0-build-foundation.md
---

# Claim 说明

实现 M0 的 freestanding x86_64 构建骨架、链接布局、确定性磁盘镜像、工具检测、
QEMU 运行入口和相应文档。
