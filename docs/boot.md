# M2 Legacy BIOS 启动链

## 启动过程

```text
BIOS
  |  加载 LBA 0 -> 0000:7c00
  v
stage1（16-bit real mode，严格 512 bytes）
  |-- 初始化段寄存器/栈并保存 BIOS DL
  |-- 输出 S1，检查 INT 13h extensions
  |-- LBA 1..127 -> physical 0x8000（失败重试，最终 E1）
  |-- 校验 "S2OK"（失败 E2）
  v
stage2（16-bit real mode，入口 physical 0x8004）
  |-- 输出 S2，启用 A20
  |-- INT 15h E820 -> boot_info/E820 buffer
  |-- LBA 128... -> physical 0x20000 ELF staging buffer
  |-- 加载临时 GDT，进入 32-bit protected mode
  v
stage2（32-bit protected mode）
  |-- 检查 CPU long-mode 能力
  |-- 验证 ELF64 header 和 program headers
  |-- 用 E820 确认 PT_LOAD 物理范围可用
  |-- PT_LOAD -> p_paddr，并清零 BSS
  |-- 建立低 1 GiB identity map 与 64 MiB higher-half map
  |-- 开启 CR4.PAE、EFER.LME、CR0.PG
  v
stage2（64-bit long mode）
  |-- RDI = boot_info v1
  |-- 从 boot_info 读取 ELF e_entry 并跳转
  v
kernel _start -> kernel_main
  |-- 输出 K2:LONG MODE OK
  |-- 校验并打印 boot_info、内核范围和 E820 map
  `-- 输出 K2:HALT 后停机
```

## 磁盘与早期物理内存

```text
磁盘镜像                              物理内存
LBA 0       stage1.bin       ------> 0x00007c00
LBA 1..127  stage2 区域      ------> 0x00008000..0x00017dff
LBA 128...  kernel.elf       ------> 0x00020000..0x0005ffff（暂存）
                                          |
                                          `-- ELF PT_LOAD -> 0x00100000...

0x00018000..0x0001803f  boot_info v1
0x00018100..0x000186ff  最多 64 个 E820 entry
0x00060000..0x00084fff  临时四级页表
0x0008f000 向下          模式切换栈
```

详细布局和 `boot_info` 字段见
[ADR-0005](decisions/0005-m2-loader-memory-and-boot-info.md)。内核 ELF 暂存上限为
256 KiB；这是 M2 的早期加载限制。

## 临时页表

```text
虚拟地址                                  物理地址
0x0000000000000000..0x000000003fffffff -> 同地址（低 1 GiB identity map）
0xffffffff80000000..0xffffffff83ffffff -> 0x00100000..0x040fffff
```

identity map 让切换前后的 stage2、栈、boot info 和页表继续可访问。higher-half
映射让链接到 `0xffffffff80000000` 的内核代码从物理 1 MiB 开始执行。这只是
启动页表；M4 会建立最终映射并收紧权限。

## 可观察输出

| 输出 | 意义 |
|---|---|
| `S1` / `S2` | 已进入 stage1 / stage2 |
| `E1` / `E2` | stage1 磁盘读取失败 / `S2OK` 校验失败 |
| `M2:E820 OK` | 已取得至少一个有效 E820 entry |
| `M2:DISK ERROR` | kernel ELF 磁盘读取重试后仍失败 |
| `M2:LONG MODE ERROR` | CPU 不支持 long mode |
| `M2:ELF ERROR` | ELF header、program header、segment 或入口不合法 |
| `M2:MEMORY ERROR` | E820 可用内存不能覆盖内核物理范围 |
| `M2:ELF OK` | ELF 已验证、装载，准备开启 paging |
| `K2:LONG MODE OK` | 已在 64 位 higher-half 内核运行 |
| `K2:HALT` | boot info/E820 输出完成，内核按 M2 设计停机 |

## 构建与测试

```sh
make image
make verify
make test-boot
make run
```

`make test-boot` 自动验证正常启动、损坏 `S2OK`、损坏 ELF magic 和 1 MiB
低内存四种路径。负路径只修改临时镜像，不修改 `build/toy-linux.img`。
