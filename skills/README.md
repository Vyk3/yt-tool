# skills/

承载 review、发布、迁移、排障等流程的可复用 workflow。
每个文件描述一类场景的执行步骤，与 AGENTS.md 中的原则互补。

`skills/` 负责的是：

- 高频场景的执行顺序
- 稳定的 workflow
- 需要按步骤推进的检查清单

不负责定义全局约束或命令准入标准。这类内容应写入 `rules/`。

示例文件：
- `release.md` — 发布流程 checklist
- `migration.md` — 数据库/schema 迁移安全步骤
- `troubleshooting.md` — CI 失败归因流程
- `workflow.md` — 开发期验证节奏与固定命令入口
