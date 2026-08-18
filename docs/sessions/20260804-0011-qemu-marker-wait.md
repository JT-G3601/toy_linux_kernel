# Session `20260804-0011-qemu-marker-wait`

## 元数据

- 任务：`TASK-TEST-002`
- 开始时间：2026-08-04T00:11:06+08:00
- 结束时间：2026-08-04T00:13:20+08:00
- Base revision：`5780abb`
- Claim：`docs/claims/closed/20260804-0011-qemu-marker-wait.md`
- Continues：`20260804-0001-qemu-test-timeout`

## 接手状态

- `TASK-TEST-001` 已让超时可配置并改善空输出诊断，在 Codex 沙箱 5 秒测试通过。
- 用户在交互式 WSL 中从 clean build 执行同一 5 秒命令，normal case 仍在没有
  `S1` 且 captured output 为空时超时，说明固定等待和 stdio capture 仍不可靠。

## 目标

- 串口输出写入普通文件，避开 terminal/pipe 行为差异。
- 每个场景轮询其明确的终止标记，看到后立即终止并回收 QEMU。
- 把可配置超时改为最大启动期限，而不是成功路径的固定等待时间。

## 实际修改

- `tools/test-boot.sh` 不再用 command substitution 直接捕获 QEMU stdio；每个场景
  使用独立串口文件和 QEMU diagnostic 文件，消除 terminal/pipe 行为差异。
- `run_qemu` 接收场景终止标记，后台启动 QEMU 并轮询串口；看到标记后立即 TERM、
  `wait` 回收 QEMU，再执行完整 marker 断言。
- 默认 `QEMU_TEST_TIMEOUT` 从 5 秒改为 30 秒，并限制为带可选 `s` 后缀的正整数；
  它现在只是最大期限，成功路径不会等待满时限。
- EXIT cleanup 会回收仍在运行的 QEMU 和临时目录，降低测试中断后的残留风险。
- README、build 参考、M2 教材和项目状态同步为 marker-driven 完成语义。

## 验证

| 命令/检查 | 结果 | 关键输出或说明 |
|---|---|---|
| `bash -n tools/test-boot.sh` | `PASS` | shell 语法通过 |
| `make test-boot` | `PASS` | 默认最大 30 秒，四场景约 0.9 秒完成 |
| `make QEMU_TEST_TIMEOUT=5s test-boot` | `PASS` | 四个终止标记均被观察并立即完成 |
| QEMU 残留进程检查 | `PASS` | 测试结束后没有匹配 `toy-linux.img` 的 QEMU |
| `make QEMU_TEST_TIMEOUT=0.5s test-boot` | `PASS` | 预期拒绝非整数参数，状态非零且错误明确 |
| `git diff --check` | `PASS` | 无 whitespace error |

## 未完成与风险

- 最大期限仍需覆盖目标机器最坏冷启动时间；默认 30 秒不会拖慢成功测试。
- 当前由 harness 发送 TERM，不是 Guest 通过专用测试设备主动退出；未来仍可使用
  `isa-debug-exit` 编码更精确的 Guest 退出原因。
- 本会话未提交或推送，改动保留在当前工作区。

## 交接建议

- 用户应直接运行 `make test-boot`；只有 30 秒内仍看不到标记时才提高
  `QEMU_TEST_TIMEOUT`，失败输出将区分串口内容和 QEMU diagnostic。
