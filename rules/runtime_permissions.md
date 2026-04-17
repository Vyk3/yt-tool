# Runtime Permission Inventory

本文件记录项目实际生效的运行时权限与 hook 清单，用于和文档规则保持同步。

范围包括：

- Codex 本地 prefix rules
- Claude Code 项目级 `permissions.allow`
- Claude Code 项目级 hooks

目标不是复制完整配置，而是记录当前治理结论：哪些保留，哪些待确认，哪些建议移除。

## Codex Prefix Rules

### 建议保留

- `["git", "add"]`
- `["git", "checkout", "-b"]`
- `[".venv/bin/python", "-m", "pytest"]`
- `["scripts/build/macos/build_app.sh"]`
- `["gh", "run", "list"]`
- `["gh", "run", "view"]`
- `["gh", "run", "watch"]`
- `["gh", "variable", "list", "--repo", "Vyk3/yt-tool"]`
- `["curl", "-sL", "https://evermeet.cx/ffmpeg/info/ffmpeg/release"]`
- `["curl", "-sL", "https://evermeet.cx/ffmpeg/info/ffprobe/release"]`
- `["curl", "-sL", "https://api.github.com/repos/yt-dlp/FFmpeg-Builds/releases/latest"]`

### 待确认

- `["gh", "variable", "set"]`
- `["gh", "workflow", "run"]`
- `[".venv/bin/python3", "-m", "pip", "install"]`
- `[".venv/bin/python", "-m", "PyInstaller"]`

说明：

- 以上四条当前继续保留，但属于后续 review 时需要再次确认的范围。

### 建议移除

- 当前无。此前标记为建议移除的历史前缀已从本地 Codex 规则文件中删除。

说明：

- 已删除项主要是旧 worktree、旧 run id、一次性 URL 或历史环境准备动作。

## Claude Permissions

配置入口：`/Users/koa/Desktop/yt-tool/.claude/settings.local.json`

### 建议保留

- `Bash(claude plugin:*)`
- `Skill(codex:review)`
- `WebFetch(domain:www.anthropic.com)`
- `Bash(git status*)`
- `Bash(git diff*)`
- `Bash(git log*)`
- `Bash(git show*)`
- `Bash(git branch --list*)`
- `Bash(git branch -vv*)`
- `Bash(git remote -v*)`
- `Bash(git rev-parse*)`
- `Bash(git ls-files*)`
- `Bash(git blame*)`
- `Bash(git config --get*)`
- `Bash(git config --list*)`
- `Bash(git add *)`
- `Bash(git checkout -b *)`
- `Bash(python3 -m pytest*)`
- `Bash(ruff check*)`
- `Bash(ruff format*)`
- `Bash(python3 -c *)`
- `Bash(which *)`
- `Bash(command -v *)`
- `Bash(bash scripts/fmt.sh*)`
- `Bash(bash scripts/check_ci.sh*)`
- `Bash(.venv/bin/python3 -m pytest*)`

### 待确认

- `Bash(git commit *)`

说明：

- `python3 -c *` 经确认当前继续保留。
- `git commit *` 仍建议在后续 review 时单独确认是否应长期低摩擦放行。

### 建议移除

- 当前无必须立刻移除项。

## Claude Hooks

### 建议保留

- `.claude/hooks/filter_bash_output.sh`
- `.claude/hooks/post_compact_reminder.sh`

说明：

- 前者已经承担 Bash 输出裁剪，与输出协议方向一致。
- 后者在 compact 后重新注入关键提醒，能降低上下文压缩后的流程漂移。

### 待确认

- 当前无。

### 建议移除

- 当前无。

## 使用方式

每次进行权限修剪时，先更新实际配置，再同步更新本文件中的状态。

如果文档结论与实际配置不一致，以“需要补齐治理动作”视之，而不是默认文档已生效。
