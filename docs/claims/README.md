# Write Claims

`active/` 中每个文件代表一个正在写项目的会话；`closed/` 保存已完成、阻塞或中断的 claim。claim 不是文件锁，而是所有会话必须遵守的协作契约。

规则：

- claim 文件名必须与 `session_id` 相同。
- 每个 active claim 必须有同名的 `docs/sessions/<session-id>.md`。
- scope 使用项目根目录相对路径，目录以 `/` 结尾。
- scope 应尽可能小。
- 父目录和子目录视为冲突。
- `PROJECT_STATUS.md`、`TASKS.md`、`DECISIONS.md` 属于共享收尾文件，需要显式列入 scope。
- 不自动删除疑似过期 claim，按 `AGENTS.md` 的中断恢复流程处理。

