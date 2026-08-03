# Session `20260731-1506-m0-build-foundation`

## 元数据

- 任务：`TASK-M0-001`
- 开始时间：2026-07-31T15:06:07+08:00
- 结束时间：2026-07-31T15:22:37+08:00
- Base revision：`c3cada5`
- Claim：`docs/claims/closed/20260731-1506-m0-build-foundation.md`
- Continues：none

## 接手状态

- `main` 与 `origin/main` 同步，工作区干净。
- M0 尚未开始，当前没有 Makefile、内核源文件或构建产物。
- make/gcc/clang/ld/as/objcopy/readelf 等构建工具可用。
- QEMU 11.0.2 位于项目外的本地构建目录；GDB 未在 PATH 中检测到。

## 目标

- 建立不依赖宿主 libc 的 x86_64 freestanding 内核 ELF 构建骨架。
- 生成确定性 M0 磁盘镜像并固定早期镜像布局。
- 提供 doctor、image、run、debug、verify、clean 开发入口。
- 准确说明 M0 镜像尚无 boot sector，真正启动从 M1 开始。

## 实际修改

- 新增 Makefile，提供 `doctor`、`kernel`、`image`、`verify`、`run`、
  `debug`、`print-config`、`clean` 和 `help` 入口。
- 新增 freestanding 公共整数/指针类型、x86_64 `_start`、16 KiB bootstrap
  stack 和最小 `kernel_main`。
- 新增 higher-half linker script，将 VMA `0xffffffff80000000` 映射到
  LMA `0x00100000`，生成 RX/R/RW ELF segments。
- 新增确定性镜像工具，将 kernel ELF 放入 16 MiB 镜像的 byte 65,536。
- 新增工具 doctor 和 ELF/image verifier；验证不依赖 libc、无动态 loader、
  无未定义符号、无 W+X segment、保留区全零且 payload 逐字节一致。
- `make clean` 使用 build marker，只允许删除由本项目创建的构建目录。
- 新增 `docs/build.md` 和 `ADR-0003`，记录构建参数及 M1/M2 必须遵守的镜像契约。
- 更新 README，使构建命令、目录和 M0 状态与实际结果一致。

## 验证

| 命令/检查 | 结果 | 关键输出或说明 |
|---|---|---|
| `make doctor` | `PASS` | 0 errors；GDB 缺失产生 1 个 optional warning |
| `make clean && make image`（GCC） | `PASS` | ELF 和 16 MiB image 从干净目录生成 |
| `make image CC=clang && make verify CC=clang` | `PASS` | Clang 构建通过 |
| `make verify` | `PASS` | ELF64、higher-half entry、LMA、W^X、符号和 image layout 全部通过 |
| 两个不同绝对路径独立构建 SHA-256 | `PASS` | kernel `849287fd...a7a75`；image `6efe9e30...e21aa`，两边一致 |
| `timeout 3s make run` | `PASS` | QEMU 成功加载并保持运行，测试按预期超时终止 |
| `timeout 3s make debug QEMU_GDB_PORT=12345` | `PASS` | 获得本地 socket 权限后 GDB server 保持运行 |
| 无效 QEMU 路径 | `PASS` | `make doctor` 明确失败并返回非零 |
| `make clean BUILD_DIR=.` | `PASS` | clean guard 拒绝删除未标记目录 |
| `bash -n tools/*.sh` | `PASS` | shell 脚本语法通过 |
| `git diff --check` | `PASS` | 无 whitespace error |
| `./tools/check-project-state.sh` | `PASS` | 收尾后 0 个 active claim |

## 未完成与风险

- M0 image 刻意没有 boot sector；QEMU 不能进入 `_start`。M1/M2 将分别实现
  stage1 和 stage2。
- GDB 客户端当前未安装；QEMU GDB server 已验证，本地 TCP socket 在沙箱中需要权限。
- 现有 `kernel_main` 仅为可链接骨架，没有 console、中断、内存管理或调度功能。

## 交接建议

- M1 从 `ADR-0003` 规定的 LBA 0 写入严格 512-byte stage1，不移动 LBA 128
  的 kernel payload。
- M1 应先加入 boot signature/尺寸构建检查和可见错误码，再实现 stage2 加载。
- 当前实现位于本地 `agent/m0-build` 分支。
