# P2：YouTube 专项能力位（精简参考）

## 已落地

- 参数构建层：`buildProbeArguments(url:)`、`buildDownloadArguments(url:formatSelector:outputTemplate:ffmpegDirectory:)`
- YouTube download 专项参数：`--concurrent-fragments 4`、`--embed-thumbnail`、`--embed-chapters`、`--embed-metadata`
- probe 路径与非 YouTube URL 不附加专项参数

## 范围约束（防止边界蔓延）

下一阶段新增功能时对照：

- 非 YouTube URL 一律保持基线不变
- 不做 Cookie 默认接入
- 不做浏览器自动化
- 不做通用站点插件框架
- 不承诺解决 `Unsupported URL`

## 下一步判断清单

以下问题在决定是否继续扩展时逐项评估：

- 是否需要追加更多 YouTube 专项参数？（当前已有基础集）
- Plugin / provider 是否真正需要？（当前答案：否）
- 是否有足够收益支撑下一阶段扩展？

## 测试约束

- YouTube probe / download 参数与非 YouTube 参数须通过单测可区分
- 非 YouTube URL 的命令行须与 P1 基线保持一致（回归保护）
