from __future__ import annotations

import pytest

from app.gui.frontend import get_html


def _build_pywebview_stub() -> str:
    return """
window.pywebview = {
    api: {
        get_default_dirs: async () => ({
            video: "/tmp/video",
            audio: "/tmp/audio",
            subtitle: "/tmp/subtitle"
        }),
        check_environment: async () => ({
            ok: true,
            items: [
                {name: "python", required: true, found: true, path: "/usr/bin/python"},
                {name: "yt-dlp", required: true, found: true, path: "/usr/local/bin/yt-dlp"},
                {name: "ffmpeg", required: false, found: true, path: "/usr/local/bin/ffmpeg"}
            ]
        }),
        detect_formats: async () => ({
            title: "stub",
            video_formats: [],
            audio_formats: [],
            subtitles: [],
            auto_subtitles: []
        }),
        start_download: async () => ({ok: true, output: "ok"}),
        browse_directory: async () => null
    }
};
"""


def test_kind_switch_syncs_format_pane_and_default_save_dir() -> None:
    pytest.importorskip("playwright.sync_api")
    from playwright.sync_api import Error, sync_playwright

    html = get_html()

    with sync_playwright() as pw:
        try:
            browser = pw.chromium.launch(headless=True)
        except Error as exc:
            pytest.skip(f"playwright chromium is not available: {exc}")

        page = browser.new_page()
        try:
            page.set_content(html, wait_until="load")
            page.evaluate(_build_pywebview_stub())
            page.evaluate("initialize()")

            page.wait_for_function(
                "() => document.getElementById('saveDir').value === '/tmp/video'"
            )

            page.click("#kind .btn[data-value='audio']")
            active_pane = page.eval_on_selector(".format-tab.active", "el => el.dataset.pane")
            assert active_pane == "audioPane"
            assert page.input_value("#saveDir") == "/tmp/audio"

            page.click("#kind .btn[data-value='subtitle']")
            active_pane = page.eval_on_selector(".format-tab.active", "el => el.dataset.pane")
            assert active_pane == "subtitlePane"
            assert page.input_value("#saveDir") == "/tmp/subtitle"

            page.click("#kind .btn[data-value='playlist']")
            is_playlist_mode_visible = page.evaluate(
                "() => getComputedStyle(document.getElementById('playlistModeSection')).display !== 'none'"
            )
            assert is_playlist_mode_visible is True
        finally:
            browser.close()
