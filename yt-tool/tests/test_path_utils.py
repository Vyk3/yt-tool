"""path_utils.py 单元测试。"""
from __future__ import annotations

import os
from pathlib import Path

import pytest

from app.path_utils import ensure_dir, expand_path, resolve_download_dir


class TestExpandPath:
    def test_tilde_expanded(self):
        result = expand_path("~/foo")
        assert "~" not in str(result)
        assert str(result).endswith("foo")

    def test_absolute_unchanged(self, tmp_path):
        p = tmp_path / "bar"
        assert expand_path(str(p)) == p


class TestEnsureDir:
    def test_creates_new_dir(self, tmp_path):
        target = tmp_path / "new_dir"
        result = ensure_dir(target)
        assert result.is_dir()

    def test_creates_nested_dirs(self, tmp_path):
        target = tmp_path / "a" / "b" / "c"
        result = ensure_dir(target)
        assert result.is_dir()

    def test_existing_dir_ok(self, tmp_path):
        result = ensure_dir(tmp_path)
        assert result == tmp_path

    def test_file_path_raises(self, tmp_path):
        file_path = tmp_path / "somefile.txt"
        file_path.write_text("x")
        with pytest.raises(ValueError, match="不是目录"):
            ensure_dir(file_path)

    def test_unwritable_dir_raises(self, tmp_path):
        target = tmp_path / "readonly"
        target.mkdir()
        target.chmod(0o444)
        try:
            with pytest.raises(ValueError, match="不可写"):
                ensure_dir(target)
        finally:
            target.chmod(0o755)

    def test_tilde_path(self):
        result = ensure_dir("~/Downloads")
        assert result.is_dir()


class TestResolveDownloadDir:
    def test_configured_dir_used(self, tmp_path):
        target = tmp_path / "Videos"
        result = resolve_download_dir(target, "Videos")
        assert result == target
        assert result.is_dir()

    def test_fallback_to_candidate(self, tmp_path):
        """如果 configured 不可用，应回退到平台候选目录。"""
        result = resolve_download_dir("/nonexistent_root_12345/foo", "Videos")
        # 应该返回某个有效路径或者兜底路径
        assert isinstance(result, Path)
