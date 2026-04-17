# Claude + Codex 单源规则维护（基于本仓库）

## 结论先行

- `symlink` 就是**符号链接（软链接）**。
- 结合本仓库当前结构（根目录已有 `AGENTS.md` + `CLAUDE.md`，并可能存在 `.claude/hooks`、`.agent/skills`），推荐：
  - **把 `AGENTS.md` 作为唯一规则源（SSOT）**；
  - `CLAUDE.md` 改为软链指向 `AGENTS.md`；
  - hooks / skills 保持各自目录，不做“规则正文复制”，只在主规则中引用其职责。

---

## 1. 为什么这里要用 symlink

如果 `AGENTS.md` 与 `CLAUDE.md` 各写一份，很快会出现：

1. 更新漏改（只改一边）
2. 行为漂移（两边优先级或流程描述不一致）
3. 问题排查困难（无法确认 agent 遵循的是哪一版）

软链接可以把两者收敛到一份源文件，天然避免漂移。

---

## 2. 推荐拓扑（适配你的仓库）

```text
AGENTS.md                  # 唯一规则源（手工维护）
CLAUDE.md -> AGENTS.md     # 软链接（不手改）
.claude/hooks/             # Claude 运行时钩子（按需）
.agent/skills/             # 技能定义（按需）
scripts/check_agent_docs.sh
```

说明：

- 规则层（policy）只有 `AGENTS.md` 一份源。
- 执行层（hook/skill）仍按工具目录组织，不与规则正文重复。
- 对 Claude / Codex 来说，入口不同但内容一致。

---

## 3. 具体落地步骤

### Step A：统一主规则

先确认 `AGENTS.md` 是你希望长期维护的版本。

### Step B：把 `CLAUDE.md` 变成软链

macOS / Linux：

```bash
rm -f CLAUDE.md
ln -s AGENTS.md CLAUDE.md
```

Windows PowerShell（管理员或启用开发者模式）：

```powershell
Remove-Item CLAUDE.md -Force
New-Item -ItemType SymbolicLink -Path CLAUDE.md -Target AGENTS.md
```

### Step C：加一致性校验（CI / 本地）

运行：

```bash
bash scripts/check_agent_docs.sh
```

该脚本会：

- 优先检查 `CLAUDE.md` 是否是软链且目标为 `AGENTS.md`
- 若不是软链，则回退为“内容必须完全一致”检查（便于 Windows 特殊环境）

---

## 4. hook 与 skill 的协作边界

建议按“规则 vs 执行”分层：

- `AGENTS.md`：定义原则、优先级、验证门槛、交付格式
- `.claude/hooks/*`：定义本地执行约束（如 python 检查、命令过滤）
- `.agent/skills/*`：定义可复用任务模板（安装、生成、审查等）

关键点：

- 不把同一条规则复制进 hook/skill 文本里；只做“引用 + 实现”。
- 规则改动只改 `AGENTS.md`，hook/skill 只在行为需要变化时改。

---

## 5. 工作流建议（Claude + Codex）

1. Planner / Reviewer 规则都写在 `AGENTS.md`。
2. Claude 读取 `CLAUDE.md` 时，实际命中 `AGENTS.md`（软链）。
3. Codex 按仓库根 `AGENTS.md` 执行。
4. 提交前跑 `scripts/check_agent_docs.sh`，防止漂移。
5. 仅在 Windows 无法稳定保留软链时，退化为“双文件同内容 + 脚本强校验”。

---

## 6. 风险与降级策略

- 风险：某些 Windows/压缩工具会丢失 symlink 元数据
  - 处理：脚本回退到内容一致性检查
- 风险：团队成员直接编辑 `CLAUDE.md`
  - 处理：在 code review/CI 阶段拦截（检查 symlink 或内容一致）
- 风险：hook/skill 里复制了规则正文
  - 处理：改成引用主规则，避免多源维护

---

## 7. 一句话方案

**用 `AGENTS.md` 做唯一规则源，`CLAUDE.md` 软链过去；hook 和 skill 只承载执行逻辑，外加 CI 脚本兜底检查。**
