# Session `20260804-0029-kernel-boot-guide`

## 元数据

- 任务：`TASK-DOC-003`
- 开始时间：2026-08-04T00:29:04+08:00
- 结束时间：2026-08-04T00:35:54+08:00
- Base revision：`5780abb`
- Claim：`docs/claims/closed/20260804-0029-kernel-boot-guide.md`
- Continues：`20260804-0011-qemu-marker-wait`

## 接手状态

- M0-M2 教材已建立，但用户反馈 M2 章节仍假定了过多 GDT、selector 和模式切换
  前置知识，缺少一篇从开机到 C 内核入口的连续、细粒度讲解。
- 当前实现已验证 BIOS -> Stage1 -> Stage2 -> long mode -> `kernel_main`。
- 无 active claim；已有 M2 和测试基础设施未提交改动均予以保留。

## 目标

- 回答 M2 是否只是页表、selector 为什么按 8 增长、16/32/64 位为何不统一。
- 从机器状态和地址解释出发，逐条连接当前源码的启动过程。
- 提供 GDT/selector 位域图、模式状态图、地址转换图和跨架构对比。
- 增加官方标准与主流实现拓展阅读。

## 实际修改

- 新增 `docs/textbook/kernel-boot-deep-dive.md`，从 BIOS、Stage1 的 `CS:IP` 与
  段寄存器开始，连续讲解 Stage2 的 A20/E820/ELF、GDT、protected mode、四级
  页表、long mode、boot info、内核栈切换和 `kernel_main`。
- 用 selector 位域图和 `selector=(index<<3)|TI|RPL` 说明 `0x08/0x10/0x18/0x20`
  递增的真实原因，区分 selector 数值、descriptor 属性、执行位数和特权级。
- 补充当前启动链与模式切换 Mermaid 图、页表层级图、三套地址坐标、三次换栈、
  串口标记排障表，以及 x86 Legacy/UEFI、AArch64、RISC-V 的架构对比。
- 在根 README、教材索引和 M2 章节增加专题入口，并核对 Intel、Linux、UEFI、
  Arm 与 RISC-V 官方拓展阅读链接。
- 更新任务与项目状态；本会话只修改文档，没有更改启动代码。

## 验证

| 命令/检查 | 结果 | 关键输出或说明 |
|---|---|---|
| 教程内部链接检查 | `PASS` | README、教材索引、M2 与专题文章的仓库内目标均存在 |
| Markdown fence/关键章节检查 | `PASS` | fence 成对；GDT、selector 公式和 16384 PTE 描述存在 |
| 专题文章与源码核对 | `PASS` | selector 常量、GDT 顺序、模式切换和 32 PT/64 MiB 映射一致 |
| `git diff --check` | `PASS` | 无 whitespace error |

## 未完成与风险

- 本文精确描述当前 Legacy BIOS 路径；UEFI、AArch64 和 RISC-V 只作入口契约的
  高层对比，不代表项目已经实现这些启动路径。
- Mermaid 需要渲染器；正文同时保留表格和等宽文字说明。
- 外部规范会更新，未来修改相应章节时仍需重新核对链接和版本。
- 当前工作区保留此前未提交的 M2、测试和教材改动，本会话没有提交或推送。

## 交接建议

- 开始 M3 前先阅读本专题的状态表和串口标记表；M3 应继续按教材模板同步解释
  内核自己的 GDT、IDT/TSS、异常与硬件中断，它们和 loader 的临时 GDT 职责不同。
