# 工作流命令参考

完整工作流（TDD 节奏、格式整理、CI 确认、Playwright GUI 测试）见 [`skills/workflow.md`](../skills/workflow.md)。

## 快速参考

```bash
# 格式整理
bash scripts/fmt.sh

# CI 状态确认
bash scripts/check_ci.sh --watch

# Playwright GUI 测试
python -m pytest tests/test_gui_frontend_playwright.py -v
```
