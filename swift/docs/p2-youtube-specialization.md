# P2 决策文档：只做 YouTube 专项能力位，不扩成通用浏览器态

## 决策

`Go`，但 `P2` 只进入 YouTube 专项能力位，不进入通用浏览器态、Cookie 默认接入或站点泛化方案。

本阶段的目标是：

1. 只为 YouTube 类问题预留更高能力上限
2. 保持默认链路仍然是“纯 bundle 内 `yt-dlp` + 当前参数”
3. 把新增复杂度限制在 YouTube 命令参数拼装层，而不是扩成新的运行时子系统

本阶段明确不做：

- 不做浏览器自动化 sidecar
- 不做浏览器 Cookie 默认导入
- 不做“任意站点都可插能力位”的通用插件框架
- 不把 `missav` 一类 `Unsupported URL` 站点作为目标

## 为什么只做 YouTube

当前 repo 的实际调用面很小：

- [YtDlpProbeService.swift](/Users/koa/.codex/worktrees/yt-tool-standalone-ytdlp-eval/swift/YTTool/Services/YtDlpProbeService.swift:20) 直接拼 `["--dump-single-json", "--no-playlist", url]`
- [YtDlpDownloadService.swift](/Users/koa/.codex/worktrees/yt-tool-standalone-ytdlp-eval/swift/YTTool/Services/YtDlpDownloadService.swift:57) 直接拼下载参数数组

这意味着：

1. 现在没有站点分流层，也没有运行时配置层
2. 如果直接做“通用能力位”，很快就会把简单参数拼装扩成站点策略系统
3. 相比之下，YouTube 是唯一已经在当前验收矩阵里反复验证的主路径，值得优先获得专项能力位

因此，`P2` 的范围应当是：

- 只在 URL 已判定为 YouTube 时，允许追加一小组 YouTube 专项参数
- 非 YouTube URL 一律保持 `P1` 现状

## Stop / Go 判断

### Go 条件

- 目标被明确限定为 “提升 YouTube 能力上限”
- 新增逻辑能停留在参数选择层，不要求新的登录态/浏览器态管理
- 默认行为仍可保持当前 `stable` 基线

### Stop 条件

- 目标被改写为 “做一个通用站点扩展框架”
- 需要 Cookie 或浏览器自动化才能成立
- 需要承诺解决 `Unsupported URL`

## 方案选择

### 方案 A：只做 YouTube 参数能力位

推荐作为 `P2` 正式方向。

定义：

- 对 YouTube URL，允许追加一组显式、受控的 `yt-dlp` 参数
- 初始只预留参数注入位，不在本轮承诺具体 token/provider 集成

优点：

- 改动面最小
- 不引入新的隐私边界
- 能与 `P1` 的 `stable / nightly` 验证口径自然组合

缺点：

- 只能提升 YouTube 路线
- 不能解决 extractor 缺失型问题

### 方案 B：通用插件框架

本阶段不推荐。

原因：

- 当前 app 还没有任何“按站点分流能力”的产品抽象
- 一旦通用化，Swift 侧会被迫引入站点分类、配置来源、错误解释和更多验收矩阵
- 复杂度明显高于当前收益

### 方案 C：浏览器态 / Cookie / 自动化

本阶段直接排除。

原因：

- 超出当前产品边界
- 会引入新的隐私和运行时复杂度
- 与之前已经明确的范围约束冲突

## 最小落地形态

`P2` 不应该先做 UI，而应该先做一个最小的 YouTube 参数构建层。

### 建议形态

新增一个非常薄的参数构建点，例如：

- `buildProbeArguments(url:)`
- `buildDownloadArguments(url:formatSelector:outputTemplate:ffmpegDirectory:)`

行为要求：

1. 默认返回当前参数，不改变非 YouTube 路径
2. 仅当 URL 属于 YouTube 时，才允许附加 YouTube 专项参数
3. 参数来源先固定在代码内，不先扩成用户设置

这样做的原因是：

- 当前 probe/download 参数分别散落在两个 service 里
- 如果不先收敛到构建点，后面每加一个 YouTube 专项参数都要改两套命令拼装
- 这仍然是外科式改动，不需要引入完整策略系统

## 最小改动面

### 本轮应动

1. [YtDlpProbeService.swift](/Users/koa/.codex/worktrees/yt-tool-standalone-ytdlp-eval/swift/YTTool/Services/YtDlpProbeService.swift:20)
   - 把 probe 参数拼装收敛到单独构建点

2. [YtDlpDownloadService.swift](/Users/koa/.codex/worktrees/yt-tool-standalone-ytdlp-eval/swift/YTTool/Services/YtDlpDownloadService.swift:57)
   - 把 download 参数拼装收敛到单独构建点

3. `swift/Tests/YTToolTests/`
   - 为 “YouTube URL 才追加专项参数” 补最小单测
   - 为 “非 YouTube URL 完全不变” 补回归单测

4. `swift/docs/`
   - 记录这轮专项能力位只针对 YouTube，不改变通用 URL 支持边界

### 本轮不动

1. `BundledToolLocator`
2. `ProcessRunner`
3. bundle 二进制交付链路
4. UI 设置页或用户可见开关

## 验收项

### A. 参数边界

- YouTube probe 参数与非 YouTube probe 参数可以通过单测区分
- YouTube download 参数与非 YouTube download 参数可以通过单测区分
- 非 YouTube URL 的命令行保持与 `P1` 基线一致

### B. 运行时回归

- built app 内 YouTube probe 继续成功
- built app 内 YouTube download/cancel 继续成功
- 非 YouTube 的已有回归路径不因参数构建重构而退化

### C. 范围边界

- 文档明确写出：
  - `P2` 只针对 YouTube
  - 不引入 Cookie 默认行为
  - 不承诺解决 `Unsupported URL`

## 本轮结论

如果继续开 `P2`，正确的第一步不是“接浏览器态”，而是：

1. 先把 probe/download 的参数拼装收敛出来
2. 把能力位严格限定为 YouTube URL
3. 用最小单测和现有 YouTube 验收链路守住回归

这一步做完后，才值得再判断：

- 是否需要接入更具体的 YouTube 参数
- 是否真的需要 plugin/provider
- 是否存在足够强的收益，值得扩到下一阶段
