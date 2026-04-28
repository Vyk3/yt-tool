# P0 决策文档：先做“能力上限”而不是“站点承诺”

## 决策

`Go`，但 `P0` 范围只落在以下目标：

1. 统一 `dev / release` 的 `yt-dlp` 交付物口径
2. 把“当前 bundle 内 `yt-dlp` 具备哪些能力”做成可验证结论
3. 明确边界：本阶段提升的是能力上限，不承诺 `missav` 一类站点可用

`P0` 不进入以下范围：

- 不加 Cookie
- 不加浏览器自动化
- 不做站点专用 extractor
- 不引入 `nightly / master` 渠道切换
- 不承诺解决 `Unsupported URL`

## 背景

本轮复测确认了两个关键事实：

1. 官方 `yt-dlp_macos` standalone 确实提供可用的 impersonation targets
2. 对 `https://missav.com/`，错误从能力视角看已经不是 “缺 impersonation”，而是 `Unsupported URL`

因此，`P0` 的正确目标是：

- 先把 app 内二进制的来源和能力口径统一
- 再为后续 `P1` 的 canary / plugin / YouTube 专项能力位留出干净基线

而不是：

- 把 standalone 升级包装成 “特定站点将被解决”

## Stop / Go 判断

### Go 条件

- 官方 standalone 相比 Homebrew shim 明确提高能力上限
- 改动主要停留在打包口径和文档，不引入不可接受的复杂度
- 验证可以在当前 Swift build 链路内完成

### Stop 条件

- 如果目标被改写为 “本轮必须解决 missav”
- 或需要立刻引入 Cookie / 浏览器自动化 / 站点专用 extractor 才能成立

## 当前结论

### 已确认成立

- app 内 `yt-dlp` 应统一为官方 `yt-dlp_macos` standalone
- Homebrew `yt-dlp` 只应作为开发机上的参考安装，不应继续作为 app 内 `yt-dlp` 来源
- standalone 版本 `2026.03.17` 已验证具备可用 impersonation targets
- built app 内的 bundle 二进制已验证可运行，并能完成 YouTube probe

### 明确不成立

- “有 impersonation targets” 不等于 “`missav` 可下载”
- 这轮验证没有得到 “Cloudflare challenge 被解决后即可下载 missav” 的证据
- 对 `missav` 首页 URL，当前结论仍是 `Unsupported URL`

## 改动清单

### 本轮应落地

1. `scripts/build/swift/pinned_versions.sh`
   - 补齐 `YTDLP_SHA256`
   - 明确 dev/release 对 `yt-dlp` 的统一口径

2. `swift/README.md`
   - 记录 `P0` 决策结论
   - 明确 URL 支持边界

3. `swift/docs/m0-spike.md`
   - 把 “dev 复制本地 Homebrew yt-dlp” 的旧表述改为官方 standalone
   - 记录这轮 `impersonation / missav` 验证结论

4. `swift/docs/p0-capability-ceiling.md`
   - 固化本页决策，作为后续 `P1` 的上游依据

### 本轮明确不做

1. `scripts/build/swift/build.sh`
   - 不加 channel 切换参数

2. `prepare_binaries.py`
   - 当前无需扩范围；release 链路已支持 pinned standalone + SHA 校验

3. Swift 运行时逻辑
   - 不新增 Cookie / 浏览器态 / 站点专用逻辑

## 验收项

### A. 交付物口径

- `dev_install_binaries.sh` 安装到 `swift/YTTool/Resources/Binaries/yt-dlp` 的是官方 standalone，不是 Homebrew shim
- `prepare_binaries.py` 的 release 输入仍指向官方 `yt-dlp_macos`
- `pinned_versions.sh` 中 `YTDLP_SHA256` 已填实值

### B. bundle 内能力

- built app 内 `Contents/Resources/Binaries/yt-dlp --version` 成功
- built app 内 `Contents/Resources/Binaries/yt-dlp --list-impersonate-targets` 成功
- 输出显示存在真实可用的 impersonation targets，而不是 `curl_cffi (unavailable)`

### C. 基本回归

- `swift test --disable-sandbox --package-path swift` 通过
- `xcodebuild -project swift/YTTool.xcodeproj -scheme YTTool -configuration Debug -derivedDataPath "$PWD/tmp/xcode-derived-data" build` 通过
- `scripts/build/swift/smoke_test.sh "$PWD/tmp/xcode-derived-data/Build/Products/Debug/YTTool.app"` 通过
- built app 内 `yt-dlp --dump-single-json --no-playlist 'https://www.youtube.com/watch?v=jNQXAC9IVRw'` 可返回 `id/title`

### D. 边界说明

- 文档中必须明确写出：
  - standalone 提升的是能力上限
  - `Unsupported URL` 仍是当前边界
  - `P0` 不承诺解决 `missav` 一类站点

## 验收记录模板

后续做 `P0` 验收时，至少记录以下结果：

1. `yt-dlp --version`
2. `yt-dlp --list-impersonate-targets`
3. YouTube probe 结果
4. `swift test`
5. `xcodebuild build`
6. `smoke_test`

若其中任一失败，先区分：

- 是 bundle/构建问题
- 是 standalone 能力问题
- 还是站点 extractor 问题

不要把三者混写成同一种失败。
