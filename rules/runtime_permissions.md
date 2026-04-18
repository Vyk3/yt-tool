# Runtime Permission Inventory

本文件记录项目运行时权限治理的当前状态，用于和实际配置保持同步。

范围包括：

- Codex 本地 prefix rules
- Claude Code 项目级 `permissions.allow`
- Claude Code 项目级 hooks

目标不是复制完整配置，而是保留最值得维护的治理信息：

- 当前事实源在哪里
- 哪些项需要继续确认
- 哪些项属于特殊保留
- 最近一次修剪做了什么

实际配置始终以运行时文件为准，不在本文件中追求完整枚举。

## 事实源

### Codex

- 本地 prefix rules：`/Users/koa/.codex/rules/default.rules`

### Claude

- 项目权限配置：`/Users/koa/Desktop/yt-tool/.claude/settings.local.json`
- 项目 hooks：`.claude/hooks/filter_bash_output.sh`
- 项目 hooks：`.claude/hooks/post_compact_reminder.sh`

## 当前治理状态

### 已稳定保留的类型

- 只读 Git 查询
- 固定验证命令
- 固定脚本入口
- 与当前仓库直接相关、边界清晰的低风险本地操作

这类项的长期约束见 `rules/allowlist.md`，不在本文件里逐条展开。

## Codex Prefix Rules

### 待确认

- `["gh", "variable", "set"]`
- `["gh", "workflow", "run"]`
- `[".venv/bin/python3", "-m", "pip", "install"]`
- `[".venv/bin/python", "-m", "PyInstaller"]`

说明：

- 以上四条当前继续保留，但属于后续 review 时需要再次确认的范围。

### 最近一次修剪结果

- 已删除旧 worktree 路径绑定前缀
- 已删除旧 run id / 旧 PR 编号绑定前缀
- 已删除一次性下载 URL 与历史环境准备前缀

当前无“已知应立即删除但尚未处理”的 Codex 前缀项。

## Claude Permissions

配置入口：`/Users/koa/Desktop/yt-tool/.claude/settings.local.json`

### 待确认

- `Bash(git commit -m *)`

说明：

- `git commit` 权限已从宽泛模式收窄为 `git commit -m *`
- 该项当前可保留，但仍应在后续 review 中确认是否长期维持低摩擦放行

### 特殊保留

- `Bash(python3 -c *)`

说明：

- 该项经过讨论后决定继续保留
- 它不属于默认推荐的宽权限模式，因此需要在本文件中显式标注，而不是埋在全量清单里

当前无“已知应立即删除但尚未处理”的 Claude 权限项。

## Claude Hooks

- `.claude/hooks/filter_bash_output.sh`
- `.claude/hooks/post_compact_reminder.sh`

说明：

- 前者已经承担 Bash 输出裁剪，与输出协议方向一致。
- 后者在 compact 后重新注入关键提醒，能降低上下文压缩后的流程漂移。

当前无待确认或待移除的 hook 项。

## 维护规则

- 先改实际配置，再更新本文件
- 本文件只保留待确认项、特殊保留项和最近一次修剪结果
- 已稳定保留的低风险项不再逐条抄录
- 如果文档结论与实际配置不一致，以“需要补齐治理动作”视之，而不是默认文档已生效
