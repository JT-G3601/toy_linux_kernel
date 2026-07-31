# Codex 项目协作规则

本文件对整个项目目录生效。任何新 Codex 会话都必须先执行这里的启动流程，再修改项目。

## 1. 权威信息源

不同文档只负责一种信息，避免相互矛盾：

| 文件 | 职责 |
|---|---|
| `plan.md` | 稳定的总体目标、架构和里程碑 |
| `PROJECT_STATUS.md` | 当前已经实现并验证到什么程度 |
| `TASKS.md` | 任务状态、依赖和下一步 |
| `DECISIONS.md` / `docs/decisions/` | 已接受的设计决策及原因 |
| `docs/claims/active/` | 当前其他写会话正在负责的文件范围 |
| `docs/sessions/` | 每次会话的操作、验证、结果和交接记录 |

若内容冲突，以实际代码和测试结果为最高证据；随后依次修正
`PROJECT_STATUS.md`、`TASKS.md` 和会话日志。不得通过修改 `plan.md` 来假装功能已经完成。

## 2. 每次会话的启动流程

1. 在项目根目录运行 `./tools/project-context.sh`。
2. 完整阅读 `PROJECT_STATUS.md`、`TASKS.md`、`DECISIONS.md`。
3. 阅读 `plan.md` 中与当前任务有关的里程碑。
4. 查看 `docs/claims/active/`，确认是否有会话正在修改相同范围。
5. 查看最近的 `docs/sessions/*.md`，理解上一次操作、验证结果和未完成事项。
6. 若目录已是 Git 仓库，检查当前分支、HEAD 和工作区；已有改动默认属于用户或其他会话，不覆盖、不回滚。
7. 在动手前用 `./tools/check-project-state.sh` 检查交接资料是否自洽。

只读分析不需要 claim。任何会修改文件的会话都需要先创建 claim 和对应会话日志。

## 3. 会话 ID、claim 与写入范围

会话 ID 格式：

```text
YYYYMMDD-HHMM-简短主题
```

例如 `20260731-1530-m0-build`。同一分钟重名时添加短后缀。

开始写操作前：

1. 从 `docs/claims/TEMPLATE.md` 创建
   `docs/claims/active/<session-id>.md`。
2. 从 `docs/sessions/TEMPLATE.md` 创建
   `docs/sessions/<session-id>.md`。
3. claim 的 `scope` 必须列出将修改的最小文件或目录范围。
4. 再次运行 `./tools/check-project-state.sh`；发现 scope 重叠时停止修改，先缩小范围或完成会话交接。

一个文件在同一时刻只能有一个写会话。不要用“我的改动很小”为理由绕过 claim。

允许多个会话并行的例子：

- 会话 A claim `boot/`，会话 B claim `docs/filesystem.md`。

禁止并行的例子：

- 会话 A claim `kernel/`，会话 B claim `kernel/mm/`。
- 两个会话同时 claim `PROJECT_STATUS.md`。

共享状态文件只在会话收尾时短时间 claim。若已有会话 claim 共享状态文件，当前会话先完成代码和自己的独立日志，等待共享文件释放后再做最终交接。

## 4. 实施规则

- 一次会话只推进 `TASKS.md` 中明确的一个主任务或紧密相关的一组子任务。
- 不修改 claim 范围外的文件；需要扩大范围时，先更新 claim 并重新检查冲突。
- 保留用户和其他会话的既有改动，不执行破坏性清理。
- “已实现”“已通过”必须有代码或命令输出证据；无法运行的测试记录为 `未运行`，并说明原因。
- 新架构选择写入独立 decision 文件，不把重要决策只留在聊天记录中。
- 不把临时构建产物、PID、锁文件或磁盘镜像写入会话日志；只记录生成方式和结果。
- 错误实验也要记录结论，防止后续会话重复踩坑。

## 5. 会话收尾与中断恢复

正常收尾时按顺序完成：

1. 运行与改动相称的构建或测试。
2. 更新本会话日志：实际修改、命令、结果、遗留问题和建议下一步。
3. 更新 `TASKS.md` 中相关任务的状态。
4. 仅写入已经验证的事实到 `PROJECT_STATUS.md`。
5. 必要时更新 `DECISIONS.md`。
6. 把 claim 从 `docs/claims/active/` 移到 `docs/claims/closed/`，将状态改为 `completed` 或 `blocked`。
7. 运行 `./tools/check-project-state.sh`。

如果上一会话意外关闭，active claim 可能残留。新会话不得直接删除它：

1. 阅读对应会话日志和工作区改动。
2. 把能确认的完成情况补入旧日志。
3. 将旧 claim 标记为 `interrupted` 并移入 `docs/claims/closed/`。
4. 创建新的 session/claim，注明 `continues` 指向旧会话。
5. 从现有文件继续，不能假定未提交改动可以丢弃。

## 6. 状态用词

任务仅使用以下状态：

- `todo`：尚未开始。
- `in_progress`：有 active claim，正在实施。
- `blocked`：存在明确阻塞因素。
- `done`：实现且完成计划内验证。
- `superseded`：被另一任务或决策正式取代。

测试仅使用：

- `PASS`
- `FAIL`
- `NOT_RUN`

不要用“基本完成”“应该可用”等模糊词替代证据。

