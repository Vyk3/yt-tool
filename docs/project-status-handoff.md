# YT Tool 项目状态 Handoff

## 一、已完成工作

### 核心功能（v0.1.0 → v0.1.2+）

| 版本/PR | 里程碑 |
|---------|--------|
| 0.1.0 | Python → Swift 原生 macOS App 全面重写（SwiftUI） |
| 0.1.1 | aria2c 多连接加速、下载队列、yt-dlp 应用内自更新 |
| 0.1.2 | yt-dlp zipapp 运行时（启动 12.9s→0.5s）、arm64-only 发布 |
| #54 | 格式选择后显示预估合并大小 |
| #55 | 下载历史持久化 + History Sheet |
| #56 | 批量 URL 导入、CI 加固、代码清理 |
| #57 | Sparkle 2.x 应用自更新（Ed25519 签名、appcast.xml、GitHub Pages） |

### 工程基础设施

- **131 单元测试全绿**（10 个测试文件覆盖 Services、Models、Parser）
- **CI**：swift test + xcodebuild build + SwiftFormat 检查
- **构建**：`scripts/build/swift/build.sh --release` → `.zip` + `.dmg`
- **治理**：allowlist 管理、review gate、PR 操作约束、worktree 脚本
- **Sparkle**：Hardened Runtime + disable-library-validation entitlement

### 架构

```text
swift/YTTool/
  App/          YTToolApp.swift（入口）
  Models/       AppState, DownloadHistory, DownloadQueueItem...
  Services/     YtDlpProbeService, DownloadService, UpdateService, ProcessRunner...
  Views/        ContentView, QueueView, HistoryView, SettingsView, AppUpdateController...
```

---

## 二、后续可做的事

### 功能层

| 项 | 优先级 | 说明 |
|----|--------|------|
| GitHub Pages 启用 | P0 | repo Settings → Pages → main/docs，Sparkle appcast 才能生效 |
| 首次正式 Release + appcast 生成 | P0 | `scripts/release/generate_appcast.sh --dist-dir swift/dist` |
| 字幕下载独立模式 | P1 | 当前字幕只在 playlist 模式下可选 |
| 下载限速 / 带宽控制 | P2 | `--limit-rate` 透传 |
| 多语言 UI（中/英切换） | P2 | 当前 UI 混合中英 |
| 旧架构 Mac 支持（当前不支持） | P3 | 需 universal binary，目前仅 arm64-only |

### 工程层

| 项 | 优先级 | 说明 |
|----|--------|------|
| UI 测试 / 集成测试 | P1 | 当前 131 测试全是 Model/Service 层，无 View 测试 |
| 代码覆盖率报告 | P1 | `swift test --enable-code-coverage` + CI 集成 |
| Crash reporting | P2 | Sparkle 自带 crash reporter 或独立方案 |
| 自动化 Release workflow | P2 | CI 打 tag → build → 签名 → upload → 更新 appcast |

---

## 三、安全性测试建议

| 方向 | 具体措施 | 现状 |
|------|----------|------|
| **输入注入** | URL 输入恶意 shell 字符（`; rm -rf`、`$(cmd)`、反引号）→ 验证 ProcessRunner 不会执行 | 未覆盖 |
| **路径穿越** | 下载目标路径包含 `../`、symlink → 验证不会写入预期目录外 | 未覆盖 |
| **Cookie 文件暴露** | 验证 cookies 文件路径不被日志或 UI 完整暴露 | 未覆盖 |
| **yt-dlp 二进制完整性** | 自更新下载的二进制验证 SHA256 | 已实现 |
| **Sparkle Ed25519 签名** | appcast 被篡改时 Sparkle 拒绝安装 | Sparkle 内置 |
| **Hardened Runtime** | 禁止动态代码注入 | 已配置 |
| **环境变量继承** | ProcessRunner 不意外继承高权限环境变量 | 未覆盖 |

---

## 四、消融性测试建议

消融测试核心思想：逐一移除/禁用组件，验证系统降级行为符合预期。

| 消融场景 | 预期行为 | 测试方式 |
|----------|----------|----------|
| 移除 yt-dlp 二进制 | 启动正常，probe/download 报明确错误，不 crash | 重命名 binary → 跑 probe |
| 移除 ffmpeg/ffprobe | 下载成功但跳过转码，UI 显示 "FFmpeg unavailable" | 已有提示逻辑，需自动化验证 |
| 移除 aria2c | 自动回退内置下载器，无 crash | 测试 Aria2cLocator 返回 nil 时的路径 |
| 网络断开 | probe 超时报错，队列暂停，不无限重试 | mock ProcessRunner 返回超时 |
| storage 损坏 | 历史记录重置为空，不 crash | 写入非法 JSON → 启动 app |
| UserDefaults 清空 | 所有设置回到默认值，app 正常启动 | `defaults delete` → 验证 init |
| Sparkle 不可用 | `#if canImport(Sparkle)` 分支，app 正常但无自更新 | 已有条件编译 |
| appcast.xml 404 | Sparkle 静默失败，不弹错误弹窗 | 配置错误 URL → 检查无 crash |
| 磁盘空间不足 | 下载前预检失败，明确提示 | mock 剩余空间 < 预估大小 |
| yt-dlp 输出格式变化 | ProbeParser 返回解析错误，不 panic | 喂入异常 JSON → 验证 graceful failure |

### 建议测试文件结构

```swift
// swift/Tests/YTToolTests/SecurityTests.swift
// - testURLInputSanitization()
// - testPathTraversalRejected()
// - testMalformedProbeOutputHandled()

// swift/Tests/YTToolTests/AblationTests.swift
// - testMissingYtDlpBinary()
// - testMissingFfmpeg()
// - testCorruptedUserDefaults()
// - testCorruptedHistoryStorage()
// - testNetworkTimeout()
// - testDiskSpaceInsufficient()
```

这些测试大部分可通过 mock ProcessRunner 和文件系统操作实现，不需要真实网络或二进制。

---

## 五、文档漂移记录（2026-05-16 审计）

| 文件 | 状态 | 详情 |
|------|------|------|
| README.md / README.en.md | 漂移 | 缺少 6 个已发布功能描述（队列、历史、批量导入、aria2c、估算大小、Sparkle） |
| CHANGELOG.md | 漂移 | 0.1.2 条目后缺少 #54~#57 的 unreleased section |
| docs/KNOWN_LIMITATIONS.md | OK | |
| swift/docs/url-support-policy.md | OK | |
| swift/DEVLOG.md | OK | |
| CLAUDE.md | OK | |
| rules/README.md | OK | |
| agents/README.md | OK | Security Reviewer 已新增，内容已更新 |
| .github/*.md | OK | |
| skills/workflow/SKILL.md | OK | |
