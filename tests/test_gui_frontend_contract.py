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


def test_frontend_environment_check_supports_background_mode() -> None:
    html = get_html()
    assert "async function checkEnvironment(options = {})" in html
    assert "const background = Boolean(options && options.background);" in html
    assert "if (background) {" in html
    assert "setBusy(true);" in html
    assert "if (!background) {" in html


def test_frontend_startup_trace_is_opt_in() -> None:
    html_default = get_html()
    html_traced = get_html(startup_trace=True)
    assert "const STARTUP_TRACE = false;" in html_default
    assert "const STARTUP_TRACE = true;" in html_traced
    assert "traceStartup('window load event');" in html_traced
    assert "traceStartup('first animation frame');" in html_traced
    assert "traceStartup('second animation frame')" in html_traced
    assert "window.pywebview.api.trace_startup(event, elapsed)" in html_traced
    assert "traceStartup(background ? 'background env_check start' : 'manual env_check start');" in html_traced
