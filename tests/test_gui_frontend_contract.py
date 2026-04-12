from __future__ import annotations

from app.gui.frontend import get_html


def test_frontend_detect_formats_forwards_optional_cookies() -> None:
    html = get_html()
    assert "window.pywebview.api.detect_formats(url, cookies || null)" in html


def test_frontend_start_download_request_shape_contract() -> None:
    html = get_html()
    assert "if (currentKind === 'playlist')" in html
    assert "extraArgs = extraArgs.filter(arg => arg !== '--no-playlist');" in html
    assert "const cookies = document.getElementById('cookies').value.trim();" in html
    assert "cookies || null" in html
    assert "else if (!extraArgs.includes('--no-playlist')) {" in html
    assert "extraArgs.push('--no-playlist');" in html
    assert "const primaryFormatId = currentKind === 'playlist'" in html
    assert "currentKind === 'audio'" in html
    assert "currentKind === 'subtitle'" in html
    assert "? ''" in html
    assert "currentKind === 'subtitle' ? selectedSubtitle : ''" in html
    assert "_setActiveFormatPane('audioPane')" in html
    assert "_setActiveFormatPane('subtitlePane')" in html
    assert "${sub.label || sub.ext || '-'}" not in html
    assert "meta.textContent = sub.label || sub.ext || '-';" in html


def test_frontend_playlist_mode_controls_exist() -> None:
    html = get_html()
    assert 'id="playlistModeSection"' in html
    assert 'id="playlistMode"' in html


def test_frontend_kind_click_handler_syncs_ui() -> None:
    html = get_html()
    assert "document.querySelectorAll('#kind .btn').forEach(btn => {" in html
    assert "currentKind = btn.getAttribute('data-value');" in html
    assert "_syncKindUI();" in html
