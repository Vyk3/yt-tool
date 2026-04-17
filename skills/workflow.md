---
name: workflow
description: "yt-tool 开发工作流：TDD + 持续验证节奏、格式整理、CI 确认、Playwright GUI 测试"
---

# 工作流：持续验证开发节奏

## 新功能开发节奏（TDD 优先）

每个功能按以下顺序推进，不跳步：

```
1. Plan     → /plan 澄清目标、范围、边界条件，产出 spec
2. TDD      → 先写失败测试（pytest），再实现直到测试通过
3. Lint     → ruff check app/ tests/
4. Review   → /codex:review（符合 AGENTS.md 触发条件时）
```

**TDD 原则**：测试先于实现。先运行测试确认它失败，再写实现让它通过，再重构。

## 上线前关卡（发布 / PR merge 前）

日常开发不强制，发布链路必须全部通过：

```
5. Security  → /security-review（发布链路 / 认证 / 公共 API 变更）
6. E2E       → python -m pytest tests/test_gui_frontend_playwright.py -v
7. Coverage  → python -m pytest --cov=app tests/
```

**Playwright 前提**：
```bash
pip install playwright
playwright install chromium
```
测试文件使用 `pytest.importorskip("playwright.sync_api")`，未安装时自动 skip。

## 格式整理（commit 前）

```bash
bash scripts/fmt.sh          # 整理 app/ 和 tests/
bash scripts/fmt.sh app/gui  # 只整理指定路径
```

执行 `ruff check --fix` + `ruff format`，优先使用 `.venv/bin/ruff`，回退到系统 ruff。

## CI 状态确认（push 后 / PR merge 前）

```bash
bash scripts/check_ci.sh                      # 查询一次当前分支 CI 状态
bash scripts/check_ci.sh --watch              # 轮询直到终态（默认 60s 间隔，300s 超时）
bash scripts/check_ci.sh --branch feat/xxx    # 查询指定分支
bash scripts/check_ci.sh --json               # JSON 输出（适合自动化消费）
```

输出摘要：`passed` / `failed` / `pending` / `not_found` / `unavailable`
