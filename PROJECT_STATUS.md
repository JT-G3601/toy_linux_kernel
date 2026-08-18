# Project Status

> 这是项目当前状态的权威摘要，只记录可以由文件或验证命令支持的事实。

## 状态元数据

- 最后更新：2026-08-18
- 更新会话：`20260818-2231-m4-memory`
- 当前阶段：M4 物理与虚拟内存管理完成
- 当前里程碑：M4 `done`；下一里程碑 M5
- 项目版本：Git `agent/m3-interrupts`，基线 `fd657ea`；M3-M4 改动位于当前工作区，尚未提交或推送
- GitHub：`https://github.com/JT-G3601/toy_linux_kernel`（public）
- Draft PR：`https://github.com/JT-G3601/toy_linux_kernel/pull/2`（`agent/m2-long-mode` -> `main`）

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
  - M1 验收时使用的最小 stage2 占位程序会输出 `S2` 后停机；M2 已将其替换。
  - `make test-boot` 已验证正常 `S1 -> S2` 与损坏交接头时
    `S1 -> E2` 且不跳转的路径。
  - linker 学习型注释与 M1 实现已分别提交并推送到远程分支，已创建
    面向 `main` 的 draft PR #1。
- 已完成 M2 loader 与 long-mode 交接：
  - stage2 启用 A20，并通过 BIOS E820 收集最多 64 个 24-byte memory entries。
  - 从 LBA 128 分批读取最多 256 KiB kernel ELF，验证 ELF64/x86_64/EXEC、
    program-header 边界、higher-half `PT_LOAD`、物理范围和可执行入口。
  - 使用 E820 type 1 entry 验证内核物理加载区，复制 `PT_LOAD` 并清零 BSS。
  - 建立临时 GDT、低 1 GiB identity map 和从 `0xffffffff80000000` 开始的
    64 MiB higher-half 映射，开启 PAE/LME/paging 后进入 long mode。
  - 从 ELF `e_entry` 动态跳转，并通过 RDI 传递版本化 64-byte `boot_info v1`。
  - higher-half 内核确认 long mode，校验 boot info，打印 boot drive、内核范围和
    E820 map，最后输出 `K2:HALT`。
  - `make test-boot` 验证正常启动、损坏 stage2、非法 ELF 和 1 MiB 低内存路径。
- 已完成 M3 内核基础设施与中断：
  - 实现 `memcpy/memset/memmove/strlen`、简化 formatter、`panic` 以及同时输出
    COM1/VGA text mode 的统一 console。
  - 建立 40-byte 内核 GDT、64-bit TSS、double-fault IST1 栈和 256-entry IDT；
    汇编入口统一 CPU error code 差异并向 C 传递 160-byte interrupt frame。
  - fatal exception 打印 vector/name/error code、`RIP/CS/RFLAGS`、`RAX..R15`；
    page fault 额外打印 `CR2`，随后关中断停机。
  - 8259 PIC remap 到 vector 32..47；PIT IRQ0 配置为 100 Hz；PS/2 IRQ1 支持
    set-1 基本 ASCII 与 Shift，并通过统一 console 回显字符。
  - `make test-boot` 构建正常/divide/page-fault 三种镜像，验证 tick 前进、QEMU
    HMP 注入 `a` 键的真实 IRQ、`#DE/#PF` 寄存器帧，并回归 M2 三条失败路径。
  - 已接受 ADR-0006，并完成 `verified` M3 教材章节。
- 已完成 M4 物理与虚拟内存管理：
  - 在删除 M2 低映射前复制 `boot_info v1` 与 E820 entries；bitmap PMM 只管理
    type 1 且低于 1 GiB 的 4 KiB frames，保留低 1 MiB 与 kernel physical range。
  - PMM 分开记录 E820 管理范围、占用状态和 allocator ownership，提供统计，并对
    未对齐、越界、未管理、保留页和重复释放执行明确 panic。
  - 最终页表提供 `0xffff800000000000` HHDM、R-X/R--/RW- kernel sections 和
    唯一的 VGA 低地址页；启用 NXE、CR0.WP，并提供 map/unmap/protect/translate 与 TLB flush。
  - 实现 `0xffffc10000000000` 起、最大 16 MiB 的按页扩展 boundary-tag first-fit
    heap，支持分裂、前后合并、跨页对象与边界损坏检测。
  - 正常启动验证 64 页 PMM 压力后 free count 恢复、最终 section/低映射权限、
    VMM map/protect/unmap 和 7000-byte 跨页 heap 复用。
  - `make test-boot` 构建五种 kernel images，共验证八个 QEMU 场景；unmapped、
    read-only、NX 的真实 `#PF` error code 分别为 `0x0/0x3/0x11`，M2-M3 回归通过。
  - 已接受 ADR-0007，并完成 `verified` M4 教材章节。
- 已建立里程碑教科书文档规范：
  - M0、M1、M2 已分别配套背景、机器状态、实现方法、示意图、验证、排错、练习与
    拓展阅读章节。
  - M3-M10 必须在功能实现时同步完成 `verified` 教材章节，才能标记为 `done`。
  - 教材图文核对发现并修复 M2 higher-half 页表仅填写一半 PTE 的偏差；当前
    32 张 PT 的 16384 个 PTE 完整映射设计规定的 64 MiB。
  - 已新增从 Legacy BIOS 连续讲到 `kernel_main` 的启动深度教程，详细解释
    real/protected/long mode、段寄存器、GDT descriptor、selector 位域、ELF
    装载、页表与跨 x86 UEFI/AArch64/RISC-V 架构差异。
- QEMU 启动测试把串口写入文件并轮询每场景终止标记，看到标记后立即终止、回收
  QEMU；`QEMU_TEST_TIMEOUT` 默认 30 秒且只作为最大期限。失败会打印串口与 QEMU
  输出，避免 terminal/pipe 差异和固定等待造成误判。
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

- 内核线程和抢占式调度尚未实现。
- 用户态、系统调用、VFS 和持久化文件系统尚未实现。
- 尚无独立用户地址空间、页表中间层回收或并发内存分配测试。

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
- M2 kernel ELF 暂存区仍限制文件大小为 256 KiB，loader 仍要求物理加载范围低于
  65 MiB；M4 最终页表已替换其临时运行时映射。
- M4 PMM/HHDM 只覆盖前 1 GiB；静态三 bitmap 约占 96 KiB，直映包含 holes/MMIO，
  但 PMM 只分配 E820 type 1 RAM。
- VMM 尚不回收空的中间页表，heap 不把尾部页退还 PMM；PMM/VMM/heap 都尚无锁。
- 最终低地址只保留 VGA `0xb8000` 一页 identity mapping；完全删除需先让 console
  改用 HHDM。
- M3 仍使用 legacy 8259/PIT/PS2；只有单核 CPL0 中断入口，没有 APIC、SMP、ring 3
  stack transition 或 `swapgs`。
- keyboard 只支持 set-1 基本 ASCII/Shift；console 尚无并发锁，fatal exception
  只诊断并停机，不尝试恢复。
- QEMU GDB server 已验证，但本机还没有 GDB 客户端。

## 下一步

执行 `TASK-M5-001`：实现内核线程、上下文切换、sleep/wake 和 PIT 驱动的抢占式
round-robin。进入抢占前先根据 ADR-0007 为 PMM/VMM/heap 定义关中断或锁保护边界。

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
| 2026-08-03 | `20260803-1911-m2-long-mode` | GCC/Clang clean `make image/verify` | `PASS`，ELF64 higher-half entry `0xffffffff80000000`，镜像布局通过 |
| 2026-08-03 | `20260803-1911-m2-long-mode` | GCC/Clang `make test-boot` | `PASS`，正常进入 long mode 并打印 E820；stage2 损坏、非法 ELF、低内存负路径通过 |
| 2026-08-03 | `20260803-1911-m2-long-mode` | `make doctor` | `PASS`，0 errors；仅可选 GDB 缺失警告 |
| 2026-08-03 | `20260803-2311-textbook-docs` | M0-M2 教材结构、内部链接与图文核对 | `PASS`，三章均含规定章节；M2 页表常量与 64 MiB 布局一致 |
| 2026-08-03 | `20260803-2311-textbook-docs` | `make image/verify/test-boot` | `PASS`，修正 16384 PTE 后四条 QEMU 路径通过 |
| 2026-08-04 | `20260804-0001-qemu-test-timeout` | `make QEMU_TEST_TIMEOUT=5s test-boot` | `PASS`，四场景显示有效超时并全部通过 |
| 2026-08-04 | `20260804-0001-qemu-test-timeout` | `QEMU_TEST_TIMEOUT=0.001s` 失败诊断注入 | `PASS`，报告实际超时和空 captured output |
| 2026-08-04 | `20260804-0011-qemu-marker-wait` | marker-driven `make test-boot` | `PASS`，四场景约 0.9 秒完成并主动回收 QEMU，无残留进程 |
| 2026-08-04 | `20260804-0011-qemu-marker-wait` | `QEMU_TEST_TIMEOUT=0.5s` 参数校验 | `PASS`，拒绝非整数最大等待值并给出明确错误 |
| 2026-08-04 | `20260804-0029-kernel-boot-guide` | 启动教程内部链接、Markdown fence 与源码常量核对 | `PASS`，GDT selector、16384 PTE/64 MiB 映射与当前实现一致 |
| 2026-08-18 | `20260817-1500-publish-m2` | GCC/Clang clean `make image verify test-boot` | `PASS`，两种编译器的正常路径和三条负路径均通过 |
| 2026-08-18 | `20260817-1500-publish-m2` | 推送 `agent/m2-long-mode` | `PASS`，本地与远程实现提交均为 `2e960b3` |
| 2026-08-18 | `20260817-1500-publish-m2` | Draft PR #2 | `PASS`，open/draft/mergeable，`agent/m2-long-mode` -> `main` |
| 2026-08-18 | `20260818-2141-m3-interrupts` | GCC/Clang clean `make image verify` | `PASS`，ELF 分别为 54,880/51,088 bytes，镜像布局通过 |
| 2026-08-18 | `20260818-2141-m3-interrupts` | GCC/Clang clean `make test-boot` | `PASS`，timer/keyboard、`#DE/#PF` 与 M2 三条负路径均通过 |
| 2026-08-18 | `20260818-2141-m3-interrupts` | M3 教材链接、fence 与源码常量核对 | `PASS`，selector/vector/frame/PIT/CR2 实验地址一致 |
| 2026-08-18 | `20260818-2231-m4-memory` | GCC clean `make test-boot` | `PASS`，M4 正常/三权限 fault、M3 divide/IRQ 与 M2 三负路径共八场景通过 |
| 2026-08-18 | `20260818-2231-m4-memory` | Clang + GNU ld clean `make test-boot` | `PASS`，同一八场景通过；环境未安装 LLD |
