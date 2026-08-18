# M0-M4 构建与镜像

## 构建链

项目用 Make 驱动 GCC 或 Clang 前端，并用 GNU `ld` 链接：

- stage1：以 `-m32` 汇编，链接为地址 `0x7c00` 的 512-byte raw binary。
- stage2：以 `-m64` 汇编同一 `.S` 中的 16/32/64-bit 代码，链接到物理
  `0x8000` 的 raw binary。
- kernel：以 freestanding x86_64 C/GNU assembler 编译，由
  `kernel/linker.ld` 链接为静态 higher-half ELF64。

stage2 依赖 `kernel.elf`。每次汇编 stage2 时，Make 会计算 ELF 文件大小和读取
扇区数，通过 `KERNEL_FILE_SIZE`、`KERNEL_SECTORS` 宏嵌入 loader。ELF 超过
256 KiB 时构建直接失败。

内核关键参数包括 `-ffreestanding`、`-fno-builtin`、`-fno-stack-protector`、
`-fno-pic -fno-pie`、`-mno-red-zone`、`-mno-{mmx,sse,sse2}` 和
`-mcmodel=kernel`；不链接宿主启动文件或 libc。
调试信息固定为 DWARF 4，使当前 GNU `readelf` 能无警告读取 GCC/Clang 产物。

## 常用命令

```sh
make doctor
make image
make verify
make test-boot
make run
make debug
make clean
```

`make` 等价于 `make image`，产物只写入带安全标记的 `build/`。可以覆盖
`CC`、`LD`、`READELF`、`BUILD_DIR`、`QEMU`、`QEMU_MEMORY` 和
`QEMU_GDB_PORT`，例如 `make CC=clang image`。`KERNEL_TEST_MODE=1/2/3/4` 只用于
受控的 divide/unmapped/read-only/NX 测试镜像；日常镜像保持默认 0。

## 地址与镜像布局

| 名称 | 值 | 含义 |
|---|---:|---|
| `KERNEL_DISK_OFFSET` | 65,536 bytes / LBA 128 | kernel ELF 在镜像中的位置 |
| staging address | `0x00020000` | stage2 临时读取完整 ELF 的物理地址 |
| `KERNEL_LMA` | `0x00100000` | ELF segment 的起始物理加载地址 |
| `KERNEL_VMA` | `0xffffffff80000000` | 内核链接和执行的起始虚拟地址 |

```text
byte 0
├── LBA 0                  512 B     stage1.bin，末尾 55 AA
├── LBA 1..127          65,024 B     stage2.bin + 零填充，以 S2OK 开头
├── LBA 128...                       kernel.elf 原始字节
└── image end        16,777,216 B    其余区域全零
```

stage1 总是把完整 LBA 1..127 读到 `0x8000`。stage2 从 LBA 128 开始按构建时
扇区数分批读取 kernel ELF，然后根据 program headers 装载 segments。

## 构建产物与验证

```text
build/
├── boot/{stage1,stage2}.{o,bin}
├── kernel/kernel.elf
├── kernel/kernel.map
├── kernel/.../*.o
├── m4-tests/{divide,unmapped,read-only,nx}/...  # 独立测试镜像
└── toy-linux.img
```

`make verify` 检查 boot signature、`S2OK`、stage2 保留区、ELF64/x86_64/EXEC、
higher-half entry、1 MiB LMA、无 dynamic loader/未定义符号/W+X segment、
256 KiB staging 上限，以及各产物与镜像内容一致。

`make test-boot` 在 QEMU 验证：

1. 正常路径完成 PMM 64 页压力、VMM map/unmap、跨页 heap 复用，再证明 tick
   递增，通过 QEMU HMP 注入 `a` 键并由真实 PS/2 IRQ 回显，输出 `K4:HALT`。
2. 独立 `KERNEL_TEST_MODE=1` 镜像执行真实 `divq / 0`，打印 vector 0 和寄存器帧。
3. mode 2 读取 unmapped page，验证 `#PF error=0x0`。
4. mode 3 在 `CR0.WP=1` 下写 read-only page，验证 `#PF error=0x3`。
5. mode 4 从 NX page 取指，验证 `#PF error=0x11`。
6. 损坏 stage2 头时输出 `E2`，不交接。
7. 损坏 ELF magic 时输出 `M2:ELF ERROR`，不进入内核。
8. 仅提供 1 MiB RAM 时输出 `M2:MEMORY ERROR`，不进入内核。

测试把串口写入临时文件，并持续等待每个场景自己的终止标记。标记出现后立即
终止并回收 QEMU；默认 30 秒只是最大启动期限，可以针对环境调整：

```sh
make QEMU_TEST_TIMEOUT=60s test-boot
```

当前 M4 正常内核输出 `K4:HALT`/`K3:HALT` 后执行 `HLT`；异常镜像在诊断后
panic/halt，均
不会请求 QEMU 进程退出。因此测试 harness 在观察到场景 marker 后主动发送 TERM
并 `wait` 回收进程。键盘注入通过 `-monitor stdio` 的私有 FIFO 写入 HMP
`sendkey a`，不需要图形窗口或 host socket。若 marker 缺失，脚本会打印串口与
QEMU captured output。

## QEMU 与 GDB

`make run` 使用无图形 QEMU 和 COM1 标准输出，正常启动应依次看到 `S1`、
`S2`、M2 loader 状态、`K2:LONG MODE OK`、M4 memory marker 与 M3 IRQ/timer marker。
`make run` 的 headless 配置不注入键盘，因此会停在等待输入的 `HLT` loop；使用
`make test-boot` 观察 HMP 自动注入按键后的完整路径。

`make debug` 在首条指令前暂停，并默认在 TCP 1234 开启 GDB server：

```sh
gdb build/kernel/kernel.elf
(gdb) target remote :1234
```

完整启动契约见 [boot.md](boot.md)。
