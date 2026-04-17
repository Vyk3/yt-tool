# Rescuer

**职责**：接手卡住的任务、深度诊断、替代实现。

## 触发条件

- Builder 连续 2 轮无法推进同一问题
- 需要独立的第二次实现或诊断
- 根因不明，需要深度调查

## 调用方式

| 运行时 | 载体 | 命令 |
|--------|------|------|
| Claude Code | Codex rescue plugin | `/codex:rescue`（仅在用户要求或明确建议且得到用户同意后使用） |
| Codex CLI | 替代实现子 agent | 需用户明确授权 |

接手完成后，后续改动由 Builder 负责，不反复委托 Rescuer。
