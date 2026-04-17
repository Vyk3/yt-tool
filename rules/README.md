# rules/

按目录或文件类型补充局部规则。每个文件针对特定范围，不重复 AGENTS.md 中已有的全局约束。

示例用途：
- `python.md` — Python 特有的编码惯例、import 规范
- `ci.md` — CI/CD 配置变更的局部约束
- `gui.md` — GUI 层变更的验证要求

`.claude/rules/` 通过 symlink 指向本目录，Claude Code 可按需读取。
