# Handoff — v0.2.2 后续增强项

> 来源：PR #78 review 发现 + v0.2.2 发版后识别的改进方向
> 日期：2026-06-03

---

## 1. 代码质量

### 1.1 `recoverySuggestion` 被挪用作 sentinel marker

- **位置**：`swift/YTTool/Models/AppState.swift`
- **现状**：用 `NSError.recoverySuggestion` 字符串（如 `"USER_CANCELLED"`）区分错误类型，依赖魔法字符串匹配
- **风险**：下游如果读到非预期的 `recoverySuggestion`，逻辑会静默走错分支；字符串拼写错误无编译期保护
- **建议**：定义 `AppError` enum（`.userCancelled`, `.probeFailed(reason:)` 等），用 `catch let error as AppError` 替代字符串匹配

### 1.2 `Set<String>` + `contains(where:)` 失去 O(1) 优势

- **位置**：`swift/YTTool/Services/YtDlpArguments.swift`
- **现状**：参数集合用 `Set<String>` 存储，但查询时用 `contains(where: { $0.hasPrefix(...) })` 做 substring matching，复杂度退化为 O(n)
- **风险**：功能正确，但违背了使用 Set 的设计意图；参数量小时无性能问题，但代码可读性差
- **建议**：改用 `[String]`（明确表示有序遍历），或将 prefix 查询提取为 named method 说明意图

---

## 2. bilibili 功能增强

### ~~2.1 订阅分页~~ — 已评估，不需要

经分析 `SubscriptionPollingManager.processNewVideos`（第 147 行）：

```swift
guard let previousLastVideoID else { return }
```

首次订阅轮询只设 bookmark、不展示视频，后续轮询只检测 bookmark 之后的新内容。当前 1 页（15-20 条）覆盖度远超实际需求（UP 主不会在单个轮询间隔内发布 15+ 条视频）。

**结论**：在当前架构下，分页无用户可见收益。仅当未来改为"首次订阅展示历史视频"时才需要分页支持。

### 2.2 cookie 过期检测

- **位置**：yt-dlp 下载路径 + bilibili curl 订阅路径
- **现状**：cookie 过期后，yt-dlp 可能静默降级画质或返回笼统错误；curl 订阅不带 cookie
- **建议**：
  - 下载路径：解析 yt-dlp stderr 中的 cookie 相关警告关键词（如 `cookie`、`login`、`expired`），在 Session Log 中标注为 cookie 问题
  - 订阅路径：属于"订阅 cookie 支持"的子任务，优先级低于核心功能
- **注意**：bilibili 的 `SESSDATA` cookie 有效期约 6 个月，过期表现因 API 而异，需要实际测试确认

---

## 3. 稳健性

### 3.1 bilibili 反爬韧性

- **位置**：`BilibiliFeedService`
- **现状**：card API 被 -352 拦截时 fallback 到 seasons → view 链路，目前工作正常
- **风险**：bilibili 可能随时升级反爬策略，seasons/view 端点也可能被限制
- **建议**：
  - 增加 retry with exponential backoff（当前直接 throw）
  - 记录 API 响应码到日志，方便排查
  - 长期考虑：如果 curl TLS 指纹也被拦截，可能需要引入 cookie 或其他绕过方案

### 3.2 release workflow tag 安全检查 — ✅ 已修复

- **PR**：fix/release-workflow-guard
- **根因**：v0.2.2 发版时，tag 在 commit 合入 main 之前被推送，触发了 release workflow。该 workflow run 的 checks 被 GitHub 关联到后续同 commit 的 PR 上，导致 `publish` 显示为 fail
- **修复**：在 `build-macos` job 开头增加 `Verify tag is on main` 步骤，tag push 触发时校验 commit 是否在 main 上，不在则 fast-fail 并给出明确错误信息
- **workflow 本身的触发条件（`on: push: tags: 'v*'`）是正确的**，`publish` job 的 `if` guard 也是正确的。问题是操作顺序：应先 merge 到 main，再打 tag

---

## 优先级建议

| 编号 | 项目 | 优先级 | 理由 |
|------|------|--------|------|
| 3.2 | release workflow tag 检查 | ✅ 已修复 | — |
| 1.1 | recoverySuggestion sentinel | 中 | 影响可维护性，但功能不受影响 |
| 1.2 | Set + contains(where:) | 低 | 纯代码质量，无功能影响 |
| 3.1 | 反爬韧性 | 低 | 当前工作正常，预防性 |
| 2.2 | cookie 过期检测 | 低 | 依赖实测，scope 不确定 |

---

## 落地建议

- 1.1 + 1.2 可以合并为一个代码质量 PR
- 3.1 视实际遇到问题再处理
- 2.2 scope 较大，需要先实测 bilibili cookie 过期的具体表现再决定方案
