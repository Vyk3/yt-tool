# PR Summary

## 必填（最小集）

- Owner (Builder):
- Reviewer:
- 风险等级（Low / Medium / High）:
- 变更描述:

## 验证结果（必填）

- 已执行命令与结果：

```text
- ruff check app/ tests/
  result:
- python -m pytest tests/ -q
  result:
```

## 条件填写（仅在触发时）

### 强制多-agent（触发项）

- 是否触发：是 / 否
- 理由（发布流程/打包链路/CI基础设施/公共契约/跨平台修复/连续回归修复）:

### 回滚策略（Medium/High 建议必填）

- 回滚触发条件:
- 回滚步骤:

### 迁移说明（有行为/接口变化时必填）

- 受影响对象:
- 旧行为 vs 新行为:
- 升级步骤:
- 回退步骤:

### Review 输出（高风险推荐）

- Codex 发现:
- 已修复:
- 验证结果:
- 遗留风险:
