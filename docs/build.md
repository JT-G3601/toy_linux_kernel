# M0/M1 构建与镜像

## 目标

M0 建立可重复的 freestanding x86_64 构建链，M1 在此基础上加入 Legacy
BIOS stage1 和用于验证交接的最小 stage2：

- 能将 C 和 GNU assembler 编译成不依赖宿主 libc 的 ELF64 内核。
- 固定 higher-half 虚拟地址与早期物理加载地址。
- 生成结构确定、可由后续 bootloader 扩展的原始磁盘镜像。
- 提供工具检测、验证、QEMU 运行和清理入口。
- 生成严格 512 字节、带 `0xAA55` 签名的 stage1。
- 用 INT 13h extensions 读取 stage2，并用 VGA/COM1 输出观察交接。

M1 镜像已可由 BIOS 进入 stage1 和 stage2 占位程序，但在 M2 之前不会加载或
运行 higher-half kernel。

## 常用命令

```sh
make doctor
make
make verify
make test-boot
make print-config
make run
make debug
make clean
```

`make` 等价于 `make image`。构建产物只写入 `build/`。构建目录内含
`.tiny-linux-kernel-build` 标记；`make clean` 只删除带有该标记的目录，避免错误的
`BUILD_DIR` 覆盖项目文件。

工具路径可以覆盖：

```sh
make QEMU=/path/to/qemu-system-x86_64 \
     QEMU_IMG=/path/to/qemu-img \
     GDB=/path/to/gdb doctor
```

也可以覆盖 `CC`、`LD`、`OBJCOPY`、`READELF`、`BUILD_DIR`、
`QEMU_MEMORY` 和 `QEMU_GDB_PORT`。

## Freestanding 编译约束

内核使用的关键参数包括：

- `-ffreestanding`：不假定标准库和宿主程序启动环境。
- `-fno-builtin`：不让编译器静默引入 libc 风格调用。
- `-fno-stack-protector`：早期内核尚无 stack protector runtime。
- `-fno-pic -fno-pie`：生成由内核链接布局控制的静态地址。
- `-mno-red-zone`：中断可能使用当前栈，内核不能依赖 red zone。
- `-mno-mmx -mno-sse -mno-sse2`：初始化扩展寄存器状态前不生成相关指令。
- `-mcmodel=kernel`：使用 x86_64 higher-half kernel code model。

链接由 `kernel/linker.ld` 完全控制，不链接宿主启动文件或 libc。

## 地址与镜像布局

不要混淆以下两个地址：

| 名称 | 值 | 含义 |
|---|---:|---|
| `KERNEL_DISK_OFFSET` | 65,536 bytes / LBA 128 | kernel ELF 在磁盘镜像中的位置 |
| `KERNEL_LMA` | `0x00100000` | ELF segment 预期加载到的物理地址 |
| `KERNEL_VMA` | `0xffffffff80000000` | 内核链接和执行使用的虚拟地址 |

16 MiB M1 镜像布局：

```text
byte 0
├── LBA 0                  512 B     stage1.bin，末尾 55 AA
├── LBA 1                  512 B     M1 stage2.bin，以 S2OK 开头
├── LBA 2..127          64,512 B     为 M2 stage2 增长保留；当前全零
├── LBA 128...                       kernel.elf 原始字节
└── image end        16,777,216 B    其余区域全零
```

stage1 始终将 LBA 1..127 读取到 `0800:0000`。M2 将替换占位 stage2 并从
LBA 128 读取 ELF。
改变这些常量前，需要同步修改镜像工具、bootloader 约定和验证。

## 构建产物

```text
build/
├── boot/
│   ├── stage1.bin
│   ├── stage1.o
│   ├── stage2.bin
│   └── stage2.o
├── kernel/
│   ├── kernel.elf
│   └── kernel.map
├── kernel/.../*.o
└── toy-linux.img
```

`make verify` 检查：

- stage1 严格为 512 字节，并在字节 510..511 包含 `55 AA`。
- stage2 不超出 LBA 1..127，并以 `S2OK` 交接头开始。
- stage1、stage2 和 kernel ELF 在镜像中的字节与独立构建产物一致。
- 内核为 x86_64 ELF64 executable。
- entry 位于 higher half。
- 首个 segment 将 higher-half VMA 映射到 1 MiB LMA，且不存在 W+X segment。
- 不存在 dynamic loader 或未定义符号。
- 镜像大小正确。
- stage2 实际内容与 LBA 128 之间的未用保留区为零。
- 镜像指定偏移处与 `kernel.elf` 逐字节一致。

## QEMU 与 GDB

当前环境自动探测到：

```text
/home/godot/ai_native/QEMU_NET/qemu-build/qemu-system-x86_64
/home/godot/ai_native/QEMU_NET/qemu-build/qemu-img
```

`make run` 启动无图形 QEMU，正常情况下串口显示 `S1` 和 `S2`，随后 stage2
占位程序停机。可按 `Ctrl+C` 终止 QEMU。

`make test-boot` 自动验证正常 `S1 -> S2` 路径，以及损坏 `S2OK` 后的
`S1 -> E2` 拒绝跳转路径。详细启动契约见 [boot.md](boot.md)。

`make debug` 让 QEMU 以 `-S` 暂停，并在 TCP 1234 提供 GDB server。安装 GDB 后可在
另一个终端执行：

```sh
gdb build/kernel/kernel.elf
(gdb) target remote :1234
```

在 M2 之前，GDB 只能调试 BIOS/bootloader 路径，不能直接到达 higher-half
`kernel_main`。
