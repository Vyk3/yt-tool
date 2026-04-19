# AGENTS.md

## 角色分工

`AGENTS.md` 仅承载跨 agent 公共约束；角色专属说明维护在 [`agents/`](agents/)（人类参考，执行 agent 不自动加载）。
各角色返回格式约束见 [`agents/output_contract.md`](agents/output_contract.md)。
调用方式因运行时不同：

| 运行时 | Builder | Reviewer |
|--------|---------|----------|
| Claude Code | 主会话（Claude） | `/codex:review` 插件调用 Codex |
| Codex CLI | 主会话（Codex） | GPT-4.1 独立子 agent |

两种运行时的 Reviewer 语义等价：独立于 Builder 的评审角色，不兼任实现。

**强制多 agent 触发器**（任一满足即触发）：
- 发布流程、打包链路、CI 基础设施变更
- 对外接口 / 公共契约变更
- 跨平台行为修复（至少 2 个 OS）
- 同一问题连续 2 轮以上回归修复

---

## 验证命令

```bash
lint:  ruff check app/ tests/
test:  python -m pytest tests/ -q
```

详细工作流命令（TDD 节奏、格式整理、CI 确认、Playwright GUI 测试）见 `skills/workflow.md`（按需加载）。

---

## Review 触发条件

**手动触发关键词**：`review` / `code review` / `复审` / `审查当前 diff`

**建议触发（需用户确认后执行）**：
并发/异步/锁、状态流转、持久化/数据库、认证/授权、删除/不可逆操作、数据库迁移/schema 变更、公开 API 签名变更、核心共享库变更。

**默认不触发**：纯文档、纯格式化、纯 import 排序。

### 执行规则

- 常规审查：`/codex:review`；高压质疑：`/codex:adversarial-review`
- 最多 **3 轮**；Codex 返回 `PASS` / `no issues` / `looks good` 时提前结束
- diff 超 800 行按文件拆分，优先送高风险文件
- 最终报告必须包含：**Codex 发现** / **已修复** / **验证结果** / **遗留风险**

---

## CI / 合并规则

- **CI 必须全绿才能 merge**，禁止 `--admin` / `--no-verify` 绕过
- 本地测试是第一道关卡，CI 不是；本地失败禁止 push
- 同一分支连续 CI 失败 2 次 → 暂停推送，先完成失败归因
- feature branch → main 优先 squash merge，保持 main 历史线性
- PR 描述默认使用 [`.github/pull_request_template.md`](.github/pull_request_template.md) 并完整填写
- PR 命令层约束见 [`rules/pr_operations.md`](rules/pr_operations.md)

---

## Commit 前确认

每次 commit 前必须按顺序执行：

```bash
git status --short      # 确认所有改动已 staged
git diff --cached       # 确认 staged 内容与预期一致
```

---

## 操作权限

- 只读查询、本地操作（add / commit / checkout -b / 验证命令）→ 自动执行
- 远程可见操作（push / PR 创建与合并）、不可逆操作（reset --hard / release 发布）→ 需用户确认

---

## Fallback 模式

以下情况进入降级模式：不是 git 仓库 / 没有可审查 diff / Codex 不可用 / 无法运行验证命令 / 用户明确要求不调用 Codex。

降级时：只降级受影响环节，其余流程正常继续；报告中必须标注降级原因与未覆盖风险；不将降级结果包装成正式 Codex review 结论。

---

## 默认 Review Prompt

```text
仅审查当前 git diff。

关注：正确性、是否引入回归、竞态条件、资源清理、缺失的输入校验、不安全假设、缺失测试、API/schema/migration 兼容性。
忽略纯风格问题，除非影响正确性或可维护性。

返回结构：
[Critical] [Major] [Minor] [Missing tests]
每条包含：文件路径、函数/符号名、为什么重要、建议修复方向。
```

## 默认 Re-review Prompt

```text
在同一线程中复审最新 diff。
1. 确认之前的发现是否已完全修复
2. 检查修复是否引入了新的回归
3. 确认测试是否已覆盖高风险路径
4. 如无实质问题，回复 PASS

严格审查，忽略纯风格偏好，除非影响正确性。
```
