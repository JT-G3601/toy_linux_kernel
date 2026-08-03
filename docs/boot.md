# M1 Legacy BIOS 启动链

## 范围

M1 实现严格 512 字节的 stage1，并用最小 stage2 占位程序验证磁盘读取和
交接。占位程序只输出 `S2` 后停机；E820、ELF64 loader、页表和 long mode
属于 M2。

## 启动过程

```text
BIOS
  |
  | 验证 LBA 0 末尾的 55 AA，加载到 0000:7c00
  v
stage1（512 bytes）
  |-- 规范化 CS，初始化 DS/ES/SS:SP，保存 DL
  |-- 初始化 COM1，输出 S1
  |-- 检查 INT 13h extensions
  |-- AH=42h 读取 LBA 1..127 -> 0800:0000（物理 0x8000）
  |-- 失败时 reset 并重试，共 3 次；最终失败 -> E1
  |-- 检查 stage2[0..3] == "S2OK"；失败 -> E2
  v
0800:0004
stage2 M1 stub
  |-- 重建 DS/ES，保持 stage1 传入的 DL
  |-- VGA + COM1 输出 S2
  `-- 停机，等待 M2 替换
```

## 磁盘与内存布局

```text
磁盘                                      实模式内存
LBA 0      stage1.bin  512 B  ---------> 0000:7c00
LBA 1..127 stage2 保留区 ---------> 0800:0000 / physical 0x8000
LBA 128... kernel.elf              M2 将解析 ELF 后加载 segment
```

stage1 一次读取 127 个扇区。DAP buffer 使用 `0800:0000`，使 65,024 字节的
读取不跨越 16-bit offset 的 64 KiB 边界。

## 可观察输出

| 输出 | 意义 |
|---|---|
| `S1` | BIOS 已进入 stage1，且基础寄存器/串口初始化完成 |
| `S2` | stage1 已读取、校验并跳入 stage2 |
| `E1` | INT 13h extensions 不可用，或磁盘读取重试仍失败 |
| `E2` | stage2 的 `S2OK` 交接头不正确，stage1 拒绝跳转 |

上述内容同时输出至 BIOS VGA teletype 和 COM1，因此既能在图形窗口中观察，
也能由 QEMU `-serial stdio` 自动化检查。

## 构建与测试

```sh
make boot
make image
make verify
make test-boot
make run
```

`make verify` 静态检查 512-byte 尺寸、`0xAA55`、`S2OK`、镜像偏移和 ELF
布局。`make test-boot` 运行两次 QEMU：

1. 正常镜像必须观察到 `S1 -> S2`。
2. 临时镜像的 `S2OK` 首字节被损坏后，必须观察到 `S1 -> E2`，且
   不得出现 `S2`。

负路径测试只修改临时镜像，不修改 `build/toy-linux.img`。
