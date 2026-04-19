# PR 操作约束

本文件定义 PR 创建、检查、合并环节的执行约束，避免命令层面的重复失误。

## PR 描述写入

- 禁止在 `gh pr create --body "..."` 中直接内联多行正文或代码块。
- 统一使用 `--body-file`。
- 若 PR 已创建且正文有污染，使用 `gh pr edit --body-file` 覆盖修正。

## CI 终态门禁

- PR 进入 `ready` 或执行 merge 前，必须确认 CI 到达终态且为全绿。
- 不允许基于“部分 job 已通过”推进 merge。

## 多 worktree 合并策略

- 多 worktree 场景下，默认不要在 merge 命令中携带 `--delete-branch`。
- 推荐顺序：先 merge，再单独清理远端/本地分支。
- 若出现分支占用冲突（例如 `branch is already used by worktree`），按“先完成合并，再清理分支”处理，不在同一命令里混合修复。

## 异常触发复盘

- `push` / `pr create` / `pr merge` 任一命令出现异常后，任务收口前必须完成最小复盘。
- 复盘最小项：失败命令、直接影响、临时止血、永久防护去向（`rules/` / `skills/` / 脚本）。
