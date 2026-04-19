from __future__ import annotations

from app.gui.frontend import get_html


def test_frontend_detect_formats_forwards_optional_cookies() -> None:
    html = get_html()
    assert "window.pywebview.api.detect_formats(url, cookies || null)" in html


def test_frontend_playlist_mode_keeps_no_playlist_logic() -> None:
    html = get_html()
    assert "if (currentKind === 'playlist')" in html
    assert "extraArgs = extraArgs.filter(arg => arg !== '--no-playlist');" in html
    assert "else if (!extraArgs.includes('--no-playlist')) {" in html
    assert "extraArgs.push('--no-playlist');" in html


def test_frontend_kind_switch_and_playlist_controls_exist() -> None:
    html = get_html()
    assert "document.querySelectorAll('#kind .btn').forEach(btn => {" in html
    assert "currentKind = btn.getAttribute('data-value');" in html
    assert "_syncKindUI();" in html
    assert 'id="playlistModeSection"' in html
    assert 'id="playlistMode"' in html
