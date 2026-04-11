# Release Checklist

## 1. 代码与功能
- [x] 四个业务分支均可运行：video / audio / subs / all
- [x] `video only` 自动补选音频逻辑正常
- [x] 下载成功时无 traceback
- [x] 下载失败时错误提示清晰
- [x] 默认下载目录逻辑正常
- [x] 路径为空、路径非法、路径不可写时可正确处理

## 2. 启动入口
- [x] `python3 -m app` 可运行
- [x] 默认入口策略：先 GUI，失败回退 CLI
- [x] 强制 CLI：`--cli` 与 `YT_TOOL_MODE=cli` 可用
- [x] Mac `yt.command` 可运行
- [ ] Windows `yt.cmd` 已验证
- [ ] Windows `yt.ps1` 已验证
- [x] URL 参数透传正常
- [x] 不带参数时可进入交互模式

## 3. 测试
- [x] pytest 全部通过 (122/122)
- [x] 关键冒烟联调已通过 (7/7)
- [x] 关键异常联调已通过 (9/9)
- [x] 回归测试已通过
- [x] 已知限制文档已更新

## 4. 文档
- [x] README 已更新
- [x] KNOWN_LIMITATIONS.md 已更新
- [x] TEST_REPORT.md 已更新
- [x] 安装方式与使用方式已写清
- [x] 支持平台已写清

## 5. 发布准备
- [x] 确认版本号 (v0.0.1)
- [x] 提交 git commit
- [x] 打 git tag (v0.0.1)
- [x] 准备 release note

## 6. Packaging
- [ ] 验证 launcher 与 `python -m app` 入口策略一致（GUI 优先，失败回退 CLI）
- [ ] 验证 `--cli` 与 `YT_TOOL_MODE=cli` 在 macOS/Windows 可用
- [ ] 验证 `requirements.txt`（含 GUI 依赖）可在干净环境安装
- [ ] 验证 ffmpeg 在目标分发机器可用
