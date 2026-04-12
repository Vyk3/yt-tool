from __future__ import annotations

from unittest.mock import Mock, patch

from app.gui import main as gui_main


def test_main_returns_error_when_webview_missing(monkeypatch, capsys) -> None:
    """Test that main returns 2 when pywebview is not installed."""

    def _raise_missing(*args, **kwargs):  # type: ignore[no-untyped-def]
        raise ModuleNotFoundError("No module named 'webview'", name="webview")

    # Patch the import of webview inside main
    with patch.dict("sys.modules", {"webview": None}):
        monkeypatch.setattr("builtins.__import__", _raise_missing)

        with patch("sys.modules", {}):
            # Simulate webview not being available
            code = gui_main.main(["app.gui.main"])

            captured = capsys.readouterr()
            assert code == 2
            assert "pywebview" in captured.err


def test_main_creates_window_and_starts(monkeypatch) -> None:
    """Test that main creates a window and starts webview."""
    mock_window = Mock()
    mock_loaded = Mock()
    mock_loaded.__iadd__ = Mock(return_value=mock_loaded)
    mock_window.events.loaded = mock_loaded
    mock_window.evaluate_js = Mock()

    mock_webview = Mock()
    mock_webview.create_window.return_value = mock_window
    mock_webview.FOLDER_DIALOG = 1
    mock_webview.start = Mock()

    with patch.dict("sys.modules", {"webview": mock_webview}):
        code = gui_main.main(["app.gui.main"])
        assert code == 0
        mock_webview.create_window.assert_called_once()
        mock_webview.start.assert_called_once()
