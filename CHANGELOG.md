# Changelog

## Unreleased

### Changed
- 收敛依赖入口：`requirements.txt` -> `requirements-cli.txt`，并在打包/发布链路显式安装 `".[gui]"`。
- CI 进入矩阵收敛阶段一：主门禁为 Linux/macOS 的 Python 3.12，新增 Linux 3.13 shadow（non-gating）。
- 下载链路重构为公共骨架：`app/core/downloader.py` 新增 `_build_download(...)`，5 类下载入口统一复用。
- 服务层类型升级为兼容 Enum：`DownloadKind`/`TaskState` 由字符串 Literal 迁移到 `str + Enum`，保留 legacy 字符串输入兼容。
- 打包脚本统一 ffmpeg 准备逻辑：新增 `scripts/build/common/prepare_ffmpeg.py`，macOS/Windows wrapper 仅做参数转发。
- 平台检测统一来源：`platform.system()` 统一收敛到 `app/core/config.py` 常量。

### Added
- `MIGRATION_NOTES.md`：记录本轮行为变更、升级步骤与回退方案。
- `tests/test_prepare_ffmpeg.py`：覆盖 ffmpeg 预检约束与缓存命中语义回归。
- 下载参数金样测试：`tests/test_downloader.py` 增加 5 类下载入口参数快照测试。

### Fixed
- 修复 release workflow 安装依赖时遗漏 GUI extras 的风险。
- 修复 workflow 在未知 `kind` 输入下可能抛异常的问题，统一返回结构化错误。

### Verified
- 本地质量门禁：`ruff check app/ tests/` + `pytest tests/ -q` 持续通过。
- macOS 本地打包验收：`bash scripts/build/macos/build_app.sh --clean` 已生成 `.app` 与 `.dmg`。
