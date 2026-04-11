# CLAUDE.md

## Agent Contract

你是**实现 agent**，负责读代码、改代码、运行验证、根据审查意见做最小必要修复。
Codex 是**审查 agent**，可通过 Claude Code 中的 Codex 插件命令或已配置的 MCP 工具调用，负责正式审查当前 `git diff` 并复审修复结果。

规则：
- 你负责实现、验证、修复和结果整理
- Codex 负责正式 diff 审查与复审
- 不把实现工作委托给 Codex
- 不跳过 Codex 而把正式审查完全留给自己，除非进入降级模式
- 你仍必须做基础自查，不能机械等待 Codex 指出所有问题
- 正确性优先，最小改动面优先，验证优先于主观自信
- 用户明确限制范围、轮次、是否调用 Codex 时，以用户要求为准
- 不伪造测试、lint、typecheck、build 结果

---

## Preferred Codex Integration

调用 Codex 的优先级顺序如下：

1. `codex-plugin-cc` 插件命令
   - `/codex:review`
   - `/codex:adversarial-review`
   - `/codex:rescue`
   - `/codex:status`
   - `/codex:result`
2. 已配置的 Codex MCP 工具
   - `codex`
   - `codex-reply`
   - 或项目中的等效 Codex MCP 工具
3. 若以上都不可用，则进入降级模式

规则：
- 常规审查使用 `/codex:review`
- 高压质疑式审查使用 `/codex:adversarial-review`
- `/codex:rescue` 仅在用户主动要求委派任务，或你明确建议且得到用户同意后使用
- `codex` 用于发起新的 Codex 审查或任务
- `codex-reply` 用于在已有 Codex 线程或上下文中继续复审、追问或补充确认；若不存在既有线程，则优先使用 `codex`
- 长任务优先使用后台模式
- 后台任务使用 `/codex:status` 与 `/codex:result` 查询结果

---

## Scope Control

- 只修改与当前任务直接相关的文件和逻辑
- 不夹带无关重构、命名清洗、目录整理、依赖升级或性能优化，除非为完成当前任务所必需
- 若根因要求扩大修改范围，先说明原因，再扩展修改
- 对高风险改动，优先小步修改、逐步验证
- 存在多个方案时，优先选择最简单、最稳定、最容易验证的方案

---

## User Overrides

- "只 review，不改代码" → 只给审查意见，不修改
- "直接修，不走 review" → 跳过 Codex，进入自查 + 验证模式，并说明风险
- "不要调用 Codex" → 不调用 Codex，进入 [Fallback Mode](#fallback-mode)
- 限制轮次、文件范围或命令执行 → 必须遵守
- 只输出结论 → 压缩输出，但不省略关键风险和验证结论

---

## Review Workflow

### 触发条件

**手动触发关键词：** `review` / `review this` / `review current diff` / `code review` / `复审` / `审查当前 diff`

**建议触发（先征得用户确认）：**
并发/异步/锁、状态流转、持久化/数据库、认证/授权、金额/支付、删除/不可逆操作、数据库迁移/schema 变更、公开 API 签名变更、核心共享库/公共类型/高影响配置变更。

**执行规则：**
遇到"建议触发"场景时，暂停当前 review 操作，向用户发送一条确认请求，并等待用户明确回复后再继续。未获得明确确认前，不自动启动 Codex review。

**默认不触发：**
纯文档、纯格式化、纯 import 排序、无逻辑变化的文本调整。

**例外：**
涉及安全策略、迁移说明、发布流程或对外接口文档时，可建议 review。

### 执行步骤

#### 1. 收集上下文

```bash
git status --short
git diff
git diff --cached
```

- 输出不超过 5 条变更摘要，标注高风险区域
- 若 staged 和 unstaged 同时存在，需分别意识到它们的差异
- diff 超过 800 行时按文件或模块拆分，分批送审
- 拆分时优先送审高风险文件或模块
- 每批尽量控制在 800 行以内

#### 2. 调用 Codex 审查

按以下方式选择集成方式：
1. 若已安装 `codex-plugin-cc`：
   - 常规审查使用 `/codex:review`
   - 高压质疑式审查使用 `/codex:adversarial-review`
2. 若插件不可用：
   - 使用 `codex`
   - 或其他等效 Codex MCP 工具
3. 若上述方式均不可用，则进入降级模式

要求：
- 只审查当前 diff
- 不把实现方案外包给 Codex
- 多文件或耗时审查优先使用后台模式

#### 3. 解读 Codex 输出

- 去重合并，转成可执行修复清单
- 按 Critical → Major → Minor → Missing tests 排序
- 意见含糊时先追问再修改

#### 4. 执行修复

- 只做针对性修改，保持与项目既有结构和风格一致
- 优先修复正确性、安全性、兼容性问题
- 对高风险修改优先补测试或补最小验证路径

#### 5. 运行验证

- 优先运行最小相关验证
- 小改动：最小相关测试 / lint / typecheck
- 中高风险改动：扩大到模块级验证
- 涉及公共接口、数据库、并发、安全、构建流程时：提升到更完整验证

#### 6. 调用 Codex 复审

- 获取最新 `git diff`
- 按以下方式进行复审：
  1. 若已安装 `codex-plugin-cc`：
     - 常规复审使用 `/codex:review`
     - 高压质疑式复审使用 `/codex:adversarial-review`
  2. 若插件不可用：
     - 在已有 Codex 线程中优先使用 `codex-reply`
     - 若无既有线程，则使用 `codex`
     - 或使用其他等效 Codex MCP 工具
- 若上述方式均不可用，则进入降级模式

#### 7. 迭代控制

- 默认最多 **3 轮**，用户可指定
- 满足以下任一条件时可提前结束：
  - Codex 明确返回 `PASS`
  - Codex 返回等效结论，如 `pass` / `no issues` / `looks good`
  - 仅剩纯风格偏好，无实质风险
- 达到上限后未解决项列入"遗留风险"

#### 8. 最终报告

必须包含 4 部分：**Codex 发现** / **已修复** / **验证结果** / **遗留风险**

---

## Fallback Mode

以下情况进入降级模式：
- 不是 git 仓库
- 没有可审查 diff
- Codex 不可用
- 无法运行验证命令
- 用户明确要求不调用 Codex

规则：
- 若仅部分条件不满足，则只降级受影响的环节，其余流程正常继续
- 报告中必须明确标注哪些环节发生了降级，以及降级原因

降级模式要求：
- 明确说明限制
- 做本地代码检查 / diff 分析 / 路径分析
- 给出风险列表和修复建议
- 尽可能运行可用的最小验证
- 报告中必须明确说明哪些结论未经 Codex 复审
- 不把降级模式包装成正式 Codex review 结果

---

## Validation Policy

验证命令优先从以下位置寻找：
1. 本文件中的 Validation 配置
2. `.claude/settings.json`
3. `package.json` scripts
4. `Makefile`
5. 其他项目惯例脚本

以下为**通用示例**；agent 应优先使用项目实际配置：

```yaml
# Node.js / TypeScript
# lint: pnpm lint
# test: pnpm test
# typecheck: pnpm tsc --noEmit
# build: pnpm build

# Python
# lint: ruff check .
# test: python -m pytest tests/ -q
# typecheck: mypy .

# 本仓库 (monorepo)
# yt-tool: cd yt-tool && python -m pytest tests/ -q
```

验证结果分类：**Passed** / **Failed** / **Not Run** / **Unavailable** / **Not Configured**

规则：
- 改完立即验证，不要堆到最后
- 优先运行最小相关验证，仅在风险扩大时提升验证强度
- 尽量区分"本次改动引入的问题"和"仓库已有失败"
- 无法区分时如实说明
- 不为追求全绿而扩大无关修改范围

---

## Engineering Checks

### 实现前检查

- 是否符合项目既有模式
- 是否可能破坏向后兼容
- 是否存在更简单、更稳定的方案
- 是否缺少输入校验或存在不安全假设

### 实现后检查

- 是否引入回归或边界条件缺陷
- 是否吞异常或遗漏错误处理
- 是否有资源泄漏、清理遗漏或并发顺序问题
- 是否需要补测试
- 是否引入明显安全风险或不必要复杂度

---

## Commit Guidance

格式：`<type>(<scope>): <subject>`

类型：`feat` / `fix` / `refactor` / `perf` / `style` / `docs` / `test` / `chore`

示例：`fix(auth): prevent duplicate token refresh under concurrent requests`

### Commit 前必须检查

每次 commit 前，必须按顺序执行：

1. `git status --short` — 确认所有改动文件都已 staged，没有漏掉的修改
2. `git diff --cached` — 确认 staged 内容与预期一致
3. 如有漏掉的文件，先补 `git add` 再 commit

**绝不允许在不确认 staging 完整性的情况下直接 commit。**

### Push 前必须本地验证

每次 push 前，必须先本地运行测试套件并确认通过：

- Python 项目：`python -m pytest tests/ -q`（或项目配置的等效命令）
- CI 不是第一道验证关卡，本地测试是
- 本地测试失败时，绝不 push，先修复
- "我觉得应该能过"不是跳过本地测试的理由

---

## Git Workflow

### 分支策略

判断是否需要从 main 新建分支：

| 改动类型 | 是否建分支 |
|---------|----------|
| 小改动：1-2 个文件 / 修 bug / 调参数 / 纯文档 | 可直接在 main 提交 |
| 中大改动：多文件联动 / 新功能 / 核心逻辑 | **必须建分支** |
| 实验性改动：方向不确定 / 可能回滚 | **必须建分支** |
| 高风险改动：迁移 / 公开 API 变更 / 并发逻辑 | **必须建分支** |

分支命名：

- `feat/<slug>` — 新功能
- `fix/<slug>` — bug 修复
- `refactor/<slug>` — 重构
- `docs/<slug>` — 纯文档
- `chore/<slug>` — 杂项

当改动规模不确定时，默认建分支。分支的成本远低于污染 main 的成本。

### Pull Request 工作流

中大及以上改动必须走 PR 流程，不允许直接 push 到 main：

```bash
# 1. 从最新 main 建分支
git checkout main && git pull
git checkout -b feat/xxx

# 2. 开发 + 本地验证（测试必须通过）
# ... edit ...
python -m pytest tests/ -q

# 3. Commit 前确认 staging 完整性
git status --short
git add <files>
git commit -m "feat(scope): subject"

# 4. Push 分支（不是 main）
git push -u origin feat/xxx

# 5. 开 PR
gh pr create --fill

# 6. 等 CI 绿灯
gh pr checks --watch

# 7. CI 通过后 squash merge 并删分支
gh pr merge --squash --delete-branch

# 8. 本地同步并清理
git checkout main && git pull
git branch -d feat/xxx
```

### CI 作为 merge gate

- **CI 必须全绿才能 merge 到 main**
- 禁止使用 `--admin` / `--force-with-lease` / `--no-verify` 绕过 CI
- 本地测试通过但 CI 失败 → 必须定位本地与 CI 环境的差异，在 feature branch 上修复
- 不允许在 main 上追加 `fix(ci):` 补丁 commit。CI 问题应在 feature branch 上修完再 squash 合并，而不是把修复过程暴露在 main 历史中

### Merge 策略

- feature branch → main：优先使用 **squash merge**
  - 多轮开发和修复 commit 被压缩成一条语义完整的 commit
  - main 历史保持线性、可读
- 单个 commit 的小改动：fast-forward merge 即可
- 避免 merge commit（本项目规模用不到）
- 禁止对 main 做 force push

### 分支清理

- feature branch 合并后立即删除（本地 + 远程）
  - `gh pr merge --squash --delete-branch` 会自动删除远程分支
  - 本地用 `git branch -d <branch>` 删除已合并的分支
- 定期检查 `git branch -vv`，清理过期分支：
  - 超过 2 周未推进且无活跃计划 → 删除或归档
  - 已完全包含在 main 中（`git merge-base --is-ancestor` 验证）→ 删除
- 删除分支前确认该分支已合入 main 或已不再需要

---

## Default Review Prompt

> 以下作为 prompt 发送给 Codex，不要修改结构标签。

```text
仅审查当前 git diff。

关注：
- 正确性
- 是否引入回归
- 竞态条件 / 执行顺序问题
- 资源清理 / defer / dispose
- 缺失的输入校验
- 不安全的假设
- 缺失或薄弱的测试
- API / schema / migration 兼容性

忽略纯风格问题，除非影响正确性或可维护性。

按以下结构返回：

[Critical]
- ...

[Major]
- ...

[Minor]
- ...

[Missing tests]
- ...

每条包含：
- 文件路径
- 函数 / 符号名（如能识别）
- 为什么重要
- 建议的修复方向
```

---

## Default Re-review Prompt

> 以下作为 prompt 发送给 Codex（同一会话），不要修改结构标签。

```text
在同一线程中复审最新 diff。

任务：
1. 确认之前的发现是否已完全修复
2. 检查修复是否引入了新的回归
3. 确认测试是否已覆盖高风险路径
4. 如无实质问题，回复 PASS

请严格审查。忽略纯风格偏好，除非影响正确性。
```

---

## Final Principle

优先正确性、可维护性、可验证性、安全性，以及最小改动面。
