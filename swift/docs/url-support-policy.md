# URL Support Policy

`yt-tool` 的目标不是覆盖所有可播放网页，而是稳定支持一类边界清晰、风险可控的媒体 URL。

## Supported Scope

`yt-tool` 优先支持同时满足以下条件的 URL：

- 公开可访问，不依赖用户私有登录态
- 非 DRM 受保护内容
- 可由 `yt-dlp` 现有 extractor 或 `generic` extractor 处理
- 如遇常见反爬，可由低风险的 request impersonation 解决
- 不要求浏览器自动化、代理绕行或深度站点对抗

## Default Capabilities

`yt-tool` 应优先投入以下能力：

- 使用能力完整的官方 standalone `yt-dlp`
- 保持 `ffmpeg / ffprobe` 与 `yt-dlp` 的一致打包与验证
- 明确区分错误类型：
  - DNS / 网络失败
  - Cloudflare / anti-bot challenge
  - `Unsupported URL`
  - 解析失败 / 无媒体格式
- 在不读取用户浏览器会话的前提下，支持低隐私风险的 impersonation

## Site-Specific Investments

以下能力不作为默认范围，只对高价值、相对稳定的站点按需投入：

- 新增或维护站点专用 extractor
- 处理站点私有 API、特殊 headers、referer 或请求顺序
- 针对一组结构相近的站点做有限复用支持

是否投入的判断标准：

- 用户价值是否足够高
- 站点结构是否相对稳定
- 长期维护成本是否可接受

## Out of Scope By Default

以下方案不应作为 `yt-tool` 默认产品路线：

- 自动读取浏览器 Cookie
- 默认依赖用户登录态
- 浏览器自动化抓取真实媒体地址
- 代理 / 出口绕行 / 网络规避
- DRM 内容支持

这些方案要么隐私边界较差，要么维护成本高且脆弱，不适合作为通用下载工具的默认能力。

## Extractor Principle

- `extractor` 通常针对单站点或一组高度相似站点
- 不能假设“修好一个 extractor 就能泛化到其他站点”
- 若某 URL 在越过反爬后仍落到 `generic -> Unsupported URL`，通常意味着：
  - 该站点缺少专用 extractor
  - 或页面媒体源依赖动态渲染 / 私有 API
- 这类问题是否继续支持，应按站点价值单独决策，而不是默认扩展产品边界

## Implementation Order

`yt-tool` 后续若继续增强 URL 支持能力，应按以下顺序推进：

1. 统一 `yt-dlp` 交付物，避免开发态 shim 与发布态能力不一致
2. 支持并验证低风险 impersonation
3. 完善错误分类与用户提示
4. 仅对高价值站点考虑专用 extractor
5. 不将 Cookie、浏览器自动化或 DRM 处理纳入默认支持范围

## One-Line Rule

`yt-tool` 支持“公开、非 DRM、无需用户私密会话、可由 `yt-dlp` 或低风险 impersonation 处理”的 URL；超出该边界的站点默认不支持，除非有明确的站点级投入决策。
