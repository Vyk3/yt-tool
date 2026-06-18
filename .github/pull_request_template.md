# PR Summary

## 变更描述

（简要说明本次变更的内容和目的）

## 风险等级

Low / Medium / High

## 验证结果

### PR / 普通 CI

- [ ] `swift test --disable-sandbox --package-path swift` 通过
- [ ] 其他验证（按需填写）:

### Release / 发布验收（仅发版或发布演练时填写）

- [ ] `python3 scripts/release/check_release_readiness.py v<version> --tag-ref HEAD --main-ref main` 通过
- [ ] Release workflow 终态成功
- [ ] `swift/dist/YTTool.app` bundle smoke test 通过
- [ ] `YTTool.zip` / `YTTool.dmg` 已上传
- [ ] 如更新 Sparkle：appcast 签名 PR 已创建或已合入
- [ ] 未声称 Apple Developer ID 签名或 Apple 公证通过

## 文档影响

- [ ] 无用户可见行为变化（无需更新文档）
- [ ] 已更新 CHANGELOG.md
- [ ] 已更新 README.md
- [ ] 已更新 KNOWN_LIMITATIONS.md
- [ ] 已更新 release notes / release template / 发布说明

## 回滚策略（Medium / High 建议填写）

- 回滚触发条件:
- 回滚步骤:

## 迁移说明（有行为 / 接口变化时填写）

- 受影响对象:
- 旧行为 vs 新行为:
- 升级步骤:
- 回退步骤:
