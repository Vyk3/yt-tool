# PR Summary

## 必填（最小集）

- Owner (Builder):
- Code Review（`/codex:review` / Codex 独立子 agent / 已跳过+原因）:
- 风险等级（Low / Medium / High）:
- 变更描述:

## 验证结果（必填）

- [ ] `swift test --disable-sandbox --package-path swift` 通过
- [ ] 其他构建/测试（按需填写）:

## 文档影响

- [ ] 无用户可见行为变化（无需更新文档）
- [ ] 已更新 CHANGELOG.md
- [ ] 已更新 README.md
- [ ] 已更新 KNOWN_LIMITATIONS.md
- [ ] 已更新 release notes / release template / 发布说明

## 条件填写（仅在触发时）

### 强制多-agent（触发项）

- 是否触发：是 / 否
- 理由（发布流程/打包链路/CI基础设施变更 / 对外接口或公共契约变更 / 跨平台行为修复（≥2个OS） / 同一问题连续2轮以上回归修复）:

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
