# rules/

按目录或文件类型补充局部规则。每个文件针对特定范围，不重复 AGENTS.md 中已有的全局约束。

`rules/` 负责的是：

- 约束
- 判定标准
- 触发条件
- 准入条件

不负责承载长流程步骤。需要按步骤执行的高频场景，应进入 `skills/` 或脚本入口。

示例用途：
- `python.md` — Python 特有的编码惯例、import 规范
- `ci.md` — CI/CD 配置变更的局部约束
- `gui.md` — GUI 层变更的验证要求
- `retrospective.md` — 复盘模板与长期资产去向判定
- `allowlist.md` — allow 候选的分级准入规则
- `fast_path_commands.md` — 低延迟命令执行规范
- `runtime_permissions.md` — Claude / Codex 运行时权限与 hook 治理清单

`.claude/rules/` 通过 symlink 指向本目录，Claude Code 可按需读取。
