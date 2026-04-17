# 工作流命令参考

## 格式整理（commit 前）

```bash
bash scripts/fmt.sh          # 整理 app/ 和 tests/
bash scripts/fmt.sh app/gui  # 只整理指定路径
```

执行 `ruff check --fix` + `ruff format`，优先使用 `.venv/bin/ruff`，回退到系统 ruff。

## CI 状态确认（push 后 / PR merge 前）

```bash
bash scripts/check_ci.sh                          # 查询一次当前分支 CI 状态
bash scripts/check_ci.sh --watch                  # 轮询直到终态（默认 60s 间隔，300s 超时）
bash scripts/check_ci.sh --branch feat/xxx        # 查询指定分支
bash scripts/check_ci.sh --json                   # JSON 输出（适合自动化消费）
```

输出摘要：`passed` / `failed` / `pending` / `not_found` / `unavailable`

## Playwright GUI 测试（前端改动时）

前提：需安装 Python playwright 包：

```bash
pip install playwright
playwright install chromium
```

运行测试：

```bash
python -m pytest tests/test_gui_frontend_playwright.py -v
```

测试文件使用 `pytest.importorskip("playwright.sync_api")`，未安装时自动 skip。
适用于 `app/gui/frontend.py` 或 GUI 前端 HTML/JS 改动的验证（AGENTS.md 验证顺序第 4/5 层）。
