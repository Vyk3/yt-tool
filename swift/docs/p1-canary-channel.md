# P1 设计文档：引入单一 Canary 渠道，不扩成第二条发布线

## 目标

`P1` 的目标不是“支持更多站点”，而是为 `yt-dlp` 提供一条受控的能力探针通道：

1. 默认交付物继续使用 `stable`
2. 引入单一 `canary` 渠道，用于验证更高能力上限
3. 把切换面限制在构建阶段，不引入运行时开关
4. 保持回退简单，不把 `canary` 演化成第二条正式发布线

## 决策

### 1. Canary 来源

`P1` 只引入一个 `canary` 渠道，首选 `nightly`，不同时支持 `master`。

原因：

- `nightly` 已足够覆盖“比 stable 更新”的核心目标
- 同时支持 `nightly + master` 会立刻放大变量矩阵
- 当前阶段更需要可控性，而不是最大化渠道数量

这意味着：

- `stable` = 默认正式交付物
- `nightly` = `canary`
- `master` = 暂不进入 `P1`

## 2. 切换入口

`P1` 只允许通过构建脚本参数切换渠道，不提供运行时切换。

推荐形式：

- `scripts/build/swift/dev_install_binaries.sh --channel stable`
- `scripts/build/swift/dev_install_binaries.sh --channel nightly`
- `scripts/build/swift/build.sh --channel stable`
- `scripts/build/swift/build.sh --channel nightly`

默认值必须是：

- 未显式传参时，一律走 `stable`

### 为什么不做运行时切换

运行时切换会把问题从“构建输入选择”扩大成“产品状态管理”：

- 当前渠道如何持久化
- UI 是否要暴露渠道概念
- 报障时如何确认用户到底跑的是哪条渠道
- 切回 `stable` 是否需要重装 bundle 内二进制
- 问题定位时如何区分渠道漂移和站点变化

`P1` 不解决这些问题，因此不引入运行时切换。

## 3. Stable 和 Canary 的职责区别

### Stable

`stable` 是默认交付物，职责是：

- 承担常规使用
- 承担完整回归要求
- 作为文档和验收口径的基线
- 作为失败时的回退落点

### Canary

`canary` 是诊断/内测通道，职责是：

- 用于验证更新版 `yt-dlp` 是否带来能力收益
- 用于复测特定问题在上游更新后是否改善
- 用于为后续升级 `stable` 提供证据

`canary` 不承担以下职责：

- 不作为默认发布口径
- 不承诺完整稳定性
- 不要求默认覆盖完整下载回归
- 不作为用户可见的正式功能矩阵一部分

### 这个区别对后续的影响

#### 对验证的影响

- `stable` 需要完整验证
- `canary` 只需要做能力导向的轻量验证

否则每次变更都会变成双倍回归成本。

#### 对文档的影响

- `stable` 文档描述默认行为
- `canary` 文档描述诊断用途

否则会把诊断渠道误写成正式支持矩阵。

#### 对发布的影响

- `stable` 可以继续作为日常构建与发布口径
- `canary` 仅用于本地、内测或故障排查构建

否则团队实际上会维护两条发布链。

#### 对问题定位的影响

- `stable` 失败，先看产品基线
- `canary` 失败，先看上游渠道波动

这决定了后续如何写验收结论和回退策略。

## 4. 具体方案

### A. 渠道模型

`P1` 只定义两个渠道：

- `stable`
- `nightly`

### B. 配置组织

`scripts/build/swift/pinned_versions.sh` 改为按渠道组织 `yt-dlp` 变量：

- `YTDLP_STABLE_VERSION`
- `YTDLP_STABLE_URL`
- `YTDLP_STABLE_SHA256`
- `YTDLP_NIGHTLY_VERSION`
- `YTDLP_NIGHTLY_URL`
- `YTDLP_NIGHTLY_SHA256`

`ffmpeg / ffprobe` 维持现状，不在 `P1` 增加多渠道。

### C. 脚本行为

`dev_install_binaries.sh`：

- 新增 `--channel stable|nightly`
- 默认 `stable`
- 根据 channel 选择对应 `yt-dlp` URL/SHA

`build.sh`：

- 新增 `--channel stable|nightly`
- 默认 `stable`
- release / dev 都把 channel 显式传给下游步骤

`prepare_binaries.py`：

- 尽量不改接口语义
- 仍只接收最终解析后的 URL/SHA
- 渠道选择逻辑留在 shell 脚本层

## 5. 验证矩阵

### Stable 必跑

- bundle 内 `yt-dlp --version`
- bundle 内 `yt-dlp --list-impersonate-targets`
- built app 内 YouTube probe
- `swift test --disable-sandbox --package-path swift`
- `xcodebuild -project swift/YTTool.xcodeproj -scheme YTTool -configuration Debug -derivedDataPath "$PWD/tmp/xcode-derived-data" build`
- `scripts/build/swift/smoke_test.sh "$PWD/tmp/xcode-derived-data/Build/Products/Debug/YTTool.app"`

### Canary 必跑

- bundle 内 `yt-dlp --version`
- bundle 内 `yt-dlp --list-impersonate-targets`
- built app 内 YouTube probe
- 需要时补目标站点复测

### Canary 在 P1 不要求

- 不要求完整下载回归
- 不要求成为默认 smoke 基线
- 不要求替代 stable 的发布验收

## 5.1 已执行验证记录（2026-04-27）

### Stable 对照结果

以下结果沿用 `P0` 已完成验证，用于作为 `nightly` 的基线对照：

- bundle 内 `yt-dlp --version`：`2026.03.17`
- bundle 内 `yt-dlp --list-impersonate-targets`：成功
- built app 内 YouTube probe：成功，返回 `jNQXAC9IVRw / Me at the zoo`
- `swift test --disable-sandbox --package-path swift`：通过（22/22）
- `xcodebuild -project swift/YTTool.xcodeproj -scheme YTTool -configuration Debug -derivedDataPath "$PWD/tmp/xcode-derived-data" build`：通过
- `scripts/build/swift/smoke_test.sh "$PWD/tmp/xcode-derived-data/Build/Products/Debug/YTTool.app"`：通过

### Canary（nightly）结果

以下结果为 `P1` 本轮实际执行记录：

- bundle 内 `yt-dlp --version`：`2026.04.10.235301`
- bundle 内 `yt-dlp --list-impersonate-targets`：成功
- built app 内 YouTube probe：成功，返回 `jNQXAC9IVRw / Me at the zoo`
- `xcodebuild -project swift/YTTool.xcodeproj -scheme YTTool -configuration Debug -derivedDataPath "$PWD/tmp/xcode-derived-data" build`：通过
- `scripts/build/swift/smoke_test.sh "$PWD/tmp/xcode-derived-data/Build/Products/Debug/YTTool.app"`：通过（7/7）

### 当前判断

- `nightly` 已达到 `P1` 设计中定义的最小 canary 验收门槛
- `stable` 仍保留完整基线职责，`nightly` 不替代默认发布验收
- 这轮得到的结论是“`nightly` canary 已可验证”，不是“默认渠道应立即从 `stable` 切换到 `nightly`”

## 6. 回退策略

`P1` 的回退原则必须固定：

1. 默认渠道永远是 `stable`
2. `canary` 仅用于本地验证、内测、故障排查
3. 只要 `canary` 没有明确收益，就不进入默认构建口径
4. 若 `canary` 表现不稳定，停止使用即可；不需要产品级迁移逻辑

这也是为什么切换入口必须停留在构建脚本参数层。

## 7. 本轮实现边界

### 本轮应做

1. 新增 `P1` 设计文档
2. 设计 `stable/nightly` 的变量组织方式
3. 明确脚本参数形态
4. 明确 `stable` 与 `canary` 的分层验证矩阵

### 本轮不做

1. 不接入 `master`
2. 不做运行时渠道切换
3. 不做 UI 渠道展示
4. 不做自动回滚逻辑
5. 不做 Cookie / 浏览器自动化 / 站点专用逻辑

## 8. 后续落地顺序

1. 先改 `scripts/build/swift/pinned_versions.sh`
2. 再改 `scripts/build/swift/dev_install_binaries.sh`
3. 再改 `scripts/build/swift/build.sh`
4. 按需更新 `swift/README.md` 和 `swift/docs/m0-spike.md`
5. 先做 `stable + nightly` 的最小能力验证，再决定是否继续扩范围
