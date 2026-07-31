# M0 Build Foundation

## 目标

M0 建立可重复的 freestanding x86_64 构建链，但不提前实现 M1/M2：

- 能将 C 和 GNU assembler 编译成不依赖宿主 libc 的 ELF64 内核。
- 固定 higher-half 虚拟地址与早期物理加载地址。
- 生成结构确定、可由后续 bootloader 扩展的原始磁盘镜像。
- 提供工具检测、验证、QEMU 运行和清理入口。

M0 磁盘没有 boot signature，因此 BIOS 报告 non-bootable 是预期结果，不是构建失败。

## 常用命令

```sh
make doctor
make
make verify
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

16 MiB M0 镜像布局：

```text
byte 0
├── LBA 0                  512 B     M1 stage1 保留区；M0 全零
├── LBA 1..127          65,024 B     stage2 保留区；M0 全零
├── LBA 128...                       kernel.elf 原始字节
└── image end        16,777,216 B    其余区域全零
```

M1 将填入 LBA 0 的 boot sector；M2 将实现 stage2 并从 LBA 128 读取 ELF。
改变这些常量前，需要同步修改镜像工具、bootloader 约定和验证。

## 构建产物

```text
build/
├── kernel/
│   ├── kernel.elf
│   └── kernel.map
├── kernel/.../*.o
└── toy-linux.img
```

`make verify` 检查：

- 内核为 x86_64 ELF64 executable。
- entry 位于 higher half。
- 首个 segment 将 higher-half VMA 映射到 1 MiB LMA，且不存在 W+X segment。
- 不存在 dynamic loader 或未定义符号。
- 镜像大小正确。
- boot/stage2 保留区在 M0 中全零。
- 镜像指定偏移处与 `kernel.elf` 逐字节一致。

## QEMU 与 GDB

当前环境自动探测到：

```text
/home/godot/ai_native/QEMU_NET/qemu-build/qemu-system-x86_64
/home/godot/ai_native/QEMU_NET/qemu-build/qemu-img
```

`make run` 会先输出 M0 non-bootable 提示，再启动无图形 QEMU。当前可按
`Ctrl+C` 终止 QEMU。

`make debug` 让 QEMU 以 `-S` 暂停，并在 TCP 1234 提供 GDB server。安装 GDB 后可在
另一个终端执行：

```sh
gdb build/kernel/kernel.elf
(gdb) target remote :1234
```

在 M2 之前，GDB 只能调试 BIOS/bootloader 路径，不能直接到达 higher-half
`kernel_main`。
