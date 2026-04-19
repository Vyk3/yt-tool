# Migration Notes (Unreleased)

本文档记录本轮“simplify”改造涉及的行为变化、升级步骤与回退方式。

## 1) 依赖安装入口变更

- 受影响对象：构建/CI 安装命令
- 旧行为：`requirements.txt`
- 新行为：`requirements-cli.txt`；Release 构建额外安装 `".[gui]"`
- 升级步骤：
  1. 本地/CI 改为 `pip install -r requirements-cli.txt`
  2. 需要 GUI 时追加 `pip install ".[gui]"`
- 回退步骤：
  1. 恢复对 `requirements.txt` 的引用
  2. 回滚 release workflow 的安装命令

## 2) CI 矩阵阶段一收敛

- 受影响对象：`.github/workflows/ci.yml`
- 旧行为：Linux+macOS 均跑 Python 3.12/3.13（4 组合）
- 新行为：主门禁为 Linux/macOS 的 3.12（2 组合），新增 Linux 3.13 shadow（非阻断）
- 升级步骤：
  1. 观察 shadow job 稳定性
  2. 记录平台/版本回归，决定是否进入阶段二
- 回退步骤：
  1. 恢复主门禁到 3.12/3.13 双版本矩阵

## 3) 下载链路去重（C1 Step2）

- 受影响对象：`app/core/downloader.py`
- 旧行为：5 个下载入口分别拼装参数
- 新行为：统一由 `_build_download(...)` 提供公共骨架
- 升级步骤：
  1. 保持 `tests/test_downloader.py` 金样测试为强门禁
  2. 后续新增参数时同步扩展金样快照
- 回退步骤：
  1. 回滚 `downloader.py` 到旧入口实现
  2. 保留测试，逐步重新引入重构

## 4) 服务层类型兼容升级（B2 兼容版）

- 受影响对象：`app/services/models.py`, `app/services/workflow.py`
- 旧行为：`DownloadKind/TaskState` 为字符串 Literal
- 新行为：升级为 `Enum`，并保留 legacy 字符串输入兼容
- 升级步骤：
  1. 新代码优先传 `DownloadKind`/`TaskState`
  2. 旧字符串调用可继续工作，逐步迁移
- 回退步骤：
  1. 回滚为字符串 Literal
  2. 恢复 workflow 的字符串分派逻辑

## 5) 打包脚本 ffmpeg 逻辑统一（D2 第一阶段）

- 受影响对象：`scripts/build/macos/build_app.sh`, `scripts/build/windows/build_exe.ps1`
- 旧行为：两端脚本各自维护下载/校验/提取逻辑
- 新行为：统一由 `scripts/build/common/prepare_ffmpeg.py` 实现
- 升级步骤：
  1. 保留原 CLI 参数不变（wrapper 仅转发）
  2. 用 `tests/test_prepare_ffmpeg.py` 保护 preflight 语义
- 回退步骤：
  1. 将 wrapper 回滚到原生 shell/ps1 逻辑
  2. 或在 wrapper 内保留开关，临时切回旧实现
