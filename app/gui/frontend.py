"""Apple Design Language HTML/CSS/JS frontend for yt-tool."""
from __future__ import annotations


def get_html() -> str:
    """Return complete HTML document with inline CSS and JS."""
    return """
<!DOCTYPE html>
<html lang="zh-Hans">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>yt-tool</title>
    <style>
        :root {
            --bg-primary: #F5F5F7;
            --bg-secondary: #FFFFFF;
            --bg-tertiary: #F2F2F7;
            --text-primary: #1D1D1F;
            --text-secondary: #86868B;
            --text-tertiary: #AEAEB2;
            --accent: #007AFF;
            --accent-hover: #0056CC;
            --accent-light: rgba(0, 122, 255, 0.1);
            --separator: #D1D1D6;
            --success: #34C759;
            --error: #FF3B30;
            --warning: #FF9500;
            --radius-card: 12px;
            --radius-input: 8px;
            --radius-small: 6px;
            --shadow-card: 0 0.5px 1px rgba(0,0,0,0.05), 0 1px 3px rgba(0,0,0,0.1);
            --transition: 0.2s ease;
        }

        @media (prefers-color-scheme: dark) {
            :root {
                --bg-primary: #000000;
                --bg-secondary: #1C1C1E;
                --bg-tertiary: #2C2C2E;
                --text-primary: #F5F5F7;
                --text-secondary: #8E8E93;
                --text-tertiary: #636366;
                --separator: #38383A;
                --shadow-card: 0 0.5px 1px rgba(0,0,0,0.2), 0 1px 3px rgba(0,0,0,0.3);
            }
        }

        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', system-ui, sans-serif;
            background: var(--bg-primary);
            color: var(--text-primary);
            font-size: 13px;
            line-height: 1.5;
            padding: 16px;
            -webkit-font-smoothing: antialiased;
            user-select: none;
            overflow-y: auto;
            height: 100vh;
        }

        /* Scrollbar styling */
        ::-webkit-scrollbar {
            width: 8px;
        }

        ::-webkit-scrollbar-track {
            background: transparent;
        }

        ::-webkit-scrollbar-thumb {
            background: var(--text-tertiary);
            border-radius: 4px;
        }

        ::-webkit-scrollbar-thumb:hover {
            background: var(--text-secondary);
        }

        /* Card styling */
        .card {
            background: var(--bg-secondary);
            border-radius: var(--radius-card);
            box-shadow: var(--shadow-card);
            padding: 16px;
            margin-bottom: 12px;
        }

        /* Label styling */
        .label {
            font-size: 11px;
            font-weight: 500;
            color: var(--text-secondary);
            text-transform: uppercase;
            letter-spacing: 0.3px;
            margin-bottom: 6px;
            display: block;
        }

        /* Input styling */
        input[type="text"],
        input[type="search"],
        textarea {
            border: 1px solid var(--separator);
            border-radius: var(--radius-input);
            background: var(--bg-tertiary);
            padding: 8px 12px;
            font-size: 13px;
            color: var(--text-primary);
            font-family: inherit;
            transition: var(--transition);
            width: 100%;
        }

        input[type="text"]:focus,
        input[type="search"]:focus,
        textarea:focus {
            outline: none;
            border-color: var(--accent);
            box-shadow: 0 0 0 3px var(--accent-light);
        }

        /* Button styling */
        .btn {
            border: none;
            border-radius: var(--radius-input);
            padding: 8px 20px;
            font-size: 13px;
            font-weight: 500;
            font-family: inherit;
            cursor: pointer;
            transition: var(--transition);
            white-space: nowrap;
        }

        .btn-primary {
            background: var(--accent);
            color: white;
        }

        .btn-primary:hover:not(:disabled) {
            background: var(--accent-hover);
        }

        .btn-secondary {
            background: transparent;
            color: var(--accent);
            border: 1px solid var(--accent);
        }

        .btn-secondary:hover:not(:disabled) {
            background: var(--accent-light);
        }

        .btn:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }

        /* Segmented control styling */
        .segmented-control {
            display: flex;
            gap: 0;
            width: fit-content;
        }

        .segmented-control .btn {
            padding: 6px 12px;
            border: 1px solid var(--accent);
            border-radius: 0;
            margin-right: -1px;
            background: transparent;
            color: var(--accent);
        }

        .segmented-control .btn:first-child {
            border-radius: var(--radius-input) 0 0 var(--radius-input);
        }

        .segmented-control .btn:last-child {
            border-radius: 0 var(--radius-input) var(--radius-input) 0;
            margin-right: 0;
        }

        .segmented-control .btn.selected {
            background: var(--accent);
            color: white;
            z-index: 1;
        }

        /* Input group styling */
        .input-group {
            margin-bottom: 12px;
        }

        .input-group-row {
            display: flex;
            gap: 8px;
            align-items: flex-end;
        }

        .input-group-row input {
            flex: 1;
        }

        .input-group-row .btn {
            flex-shrink: 0;
        }

        /* Grid layout for controls */
        .controls-grid {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 12px;
        }

        .controls-grid-full {
            grid-column: 1 / -1;
        }

        /* Button row */
        .button-row {
            display: flex;
            gap: 8px;
            margin-top: 12px;
        }

        /* Status bar */
        .status-bar {
            background: var(--bg-secondary);
            border-radius: var(--radius-card);
            box-shadow: var(--shadow-card);
            padding: 12px 16px;
            margin-bottom: 12px;
            display: flex;
            gap: 20px;
            font-size: 12px;
        }

        .status-item {
            display: flex;
            align-items: center;
            gap: 6px;
        }

        .status-label {
            color: var(--text-secondary);
            font-weight: 500;
        }

        .status-value {
            color: var(--text-primary);
            font-family: 'Monaco', 'Menlo', monospace;
            font-size: 11px;
        }

        /* Table styling */
        table {
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 12px;
        }

        thead {
            border-bottom: 1px solid var(--separator);
        }

        th {
            text-align: left;
            padding: 8px 12px;
            font-weight: 500;
            color: var(--text-secondary);
            font-size: 12px;
            text-transform: uppercase;
            letter-spacing: 0.3px;
        }

        td {
            padding: 8px 12px;
            border-bottom: 1px solid rgba(209, 209, 214, 0.1);
            color: var(--text-primary);
            font-size: 13px;
        }

        tbody tr:hover {
            background: var(--accent-light);
            cursor: pointer;
        }

        tbody tr.selected {
            background: var(--accent);
            color: white;
        }

        tbody tr.selected td {
            color: white;
            border-bottom-color: rgba(255, 255, 255, 0.1);
        }

        /* Log view styling */
        #logView {
            font-family: 'Monaco', 'Menlo', monospace;
            font-size: 11px;
            line-height: 1.6;
            background: var(--bg-tertiary);
            color: var(--text-primary);
            border-radius: var(--radius-card);
            padding: 12px;
            max-height: 300px;
            overflow-y: auto;
            white-space: pre-wrap;
            word-wrap: break-word;
            border: 1px solid var(--separator);
        }

        /* Subtitle list styling */
        .subtitle-item {
            padding: 8px 12px;
            background: var(--bg-tertiary);
            border: 1px solid var(--separator);
            border-radius: var(--radius-small);
            margin-bottom: 4px;
            cursor: pointer;
            transition: var(--transition);
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        .subtitle-item:hover {
            background: var(--accent-light);
        }

        .subtitle-item.selected {
            background: var(--accent);
            color: white;
            border-color: var(--accent);
        }

        .subtitle-lang {
            font-weight: 500;
        }

        .subtitle-auto {
            font-size: 11px;
            opacity: 0.7;
        }

        /* Collapsible sections */
        .collapsible-header {
            cursor: pointer;
            padding: 8px 12px;
            background: var(--bg-tertiary);
            border-radius: var(--radius-small);
            font-weight: 500;
            color: var(--text-primary);
            user-select: none;
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 8px;
        }

        .collapsible-header:hover {
            background: var(--accent-light);
        }

        .collapsible-header::after {
            content: '▼';
            font-size: 10px;
            transition: var(--transition);
            transform: rotate(-90deg);
        }

        .collapsible-header.expanded::after {
            transform: rotate(0deg);
        }

        .collapsible-content {
            display: none;
            padding-left: 12px;
            border-left: 2px solid var(--separator);
            margin-bottom: 12px;
        }

        .collapsible-content.expanded {
            display: block;
        }

        /* Busy overlay */
        .busy-overlay {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: rgba(0, 0, 0, 0.1);
            display: none;
            z-index: 1000;
        }

        .busy-overlay.active {
            display: block;
        }

        /* Tab-like layout for format results */
        .format-tabs {
            display: flex;
            gap: 8px;
            margin-bottom: 12px;
            border-bottom: 1px solid var(--separator);
        }

        .format-tab {
            padding: 8px 12px;
            border: none;
            background: transparent;
            color: var(--text-secondary);
            cursor: pointer;
            font-size: 13px;
            font-weight: 500;
            border-bottom: 2px solid transparent;
            transition: var(--transition);
        }

        .format-tab:hover {
            color: var(--text-primary);
        }

        .format-tab.active {
            color: var(--accent);
            border-bottom-color: var(--accent);
        }

        .format-pane {
            display: none;
        }

        .format-pane.active {
            display: block;
        }

        /* Error message styling */
        .error-message {
            background: rgba(255, 59, 48, 0.1);
            color: var(--error);
            border: 1px solid var(--error);
            border-radius: var(--radius-small);
            padding: 8px 12px;
            margin-bottom: 12px;
            font-size: 12px;
        }

        /* Success message styling */
        .success-message {
            background: rgba(52, 199, 89, 0.1);
            color: var(--success);
            border: 1px solid var(--success);
            border-radius: var(--radius-small);
            padding: 8px 12px;
            margin-bottom: 12px;
            font-size: 12px;
        }
    </style>
</head>
<body>
    <div class="busy-overlay" id="busyOverlay"></div>

    <!-- Input Card -->
    <div class="card">
        <label class="label">URL</label>
        <input type="text" id="url" placeholder="粘贴 YouTube 或其他视频网址" />

        <label class="label" style="margin-top: 12px;">下载类型</label>
        <div class="segmented-control" id="kind">
            <button class="btn selected" data-value="video">视频</button>
            <button class="btn" data-value="audio">音频</button>
            <button class="btn" data-value="subtitle">字幕</button>
            <button class="btn" data-value="playlist">播放列表</button>
        </div>

        <div id="playlistModeSection" style="display: none;">
            <label class="label" style="margin-top: 12px;">播放列表模式</label>
            <div class="segmented-control" id="playlistMode">
                <button class="btn selected" data-value="video">视频</button>
                <button class="btn" data-value="audio">音频</button>
            </div>
        </div>

        <label class="label" style="margin-top: 12px;">保存目录</label>
        <div class="input-group-row">
            <input type="text" id="saveDir" placeholder="选择保存目录" readonly />
            <button class="btn btn-secondary" onclick="browseSaveDir()">浏览</button>
        </div>

        <label class="label" style="margin-top: 12px;">Cookies</label>
        <input type="text" id="cookies" placeholder="可选：本地 cookies 文件路径或网址" />

        <label class="label" style="margin-top: 12px;">转码格式</label>
        <input type="text" id="transcode" placeholder="可选：mp3, m4a, wav, opus 等" />

        <label class="label" style="margin-top: 12px;">额外参数</label>
        <input type="text" id="extraArgs" placeholder="可选：--proxy socks5://... 等" />

        <div class="button-row">
            <button class="btn btn-secondary" onclick="checkEnvironment()">环境检查</button>
            <button class="btn btn-secondary" onclick="detectFormats()">探测格式</button>
            <button class="btn btn-primary" onclick="startDownload()" style="flex: 1;">开始下载</button>
        </div>
    </div>

    <!-- Status Bar -->
    <div class="status-bar">
        <div class="status-item">
            <span class="status-label">环境:</span>
            <span class="status-value" id="envStatus">未检查</span>
        </div>
        <div class="status-item">
            <span class="status-label">格式:</span>
            <span class="status-value" id="detectStatus">未探测</span>
        </div>
    </div>

    <!-- Format Results Card -->
    <div class="card" id="formatCard" style="display: none;">
        <div class="format-tabs">
            <button class="format-tab active" data-pane="videoPane">视频</button>
            <button class="format-tab" data-pane="audioPane">音频</button>
            <button class="format-tab" data-pane="subtitlePane">字幕</button>
        </div>

        <div class="format-pane active" id="videoPane">
            <table>
                <thead>
                    <tr>
                        <th style="width: 10%;">格式ID</th>
                        <th style="width: 12%;">分辨率</th>
                        <th style="width: 8%;">FPS</th>
                        <th style="width: 12%;">码率</th>
                        <th style="width: 12%;">编码</th>
                        <th style="width: 8%;">容器</th>
                        <th style="width: 10%;">大小</th>
                        <th style="width: 28%;">注</th>
                    </tr>
                </thead>
                <tbody id="videoTable">
                </tbody>
            </table>
        </div>

        <div class="format-pane" id="audioPane">
            <table>
                <thead>
                    <tr>
                        <th style="width: 15%;">格式ID</th>
                        <th style="width: 15%;">码率</th>
                        <th style="width: 15%;">编码</th>
                        <th style="width: 15%;">容器</th>
                        <th style="width: 15%;">声道</th>
                        <th style="width: 10%;">大小</th>
                    </tr>
                </thead>
                <tbody id="audioTable">
                </tbody>
            </table>
        </div>

        <div class="format-pane" id="subtitlePane">
            <div id="subtitleList">
            </div>
        </div>
    </div>

    <!-- Log Card -->
    <div class="card">
        <label class="label">日志</label>
        <pre id="logView"></pre>
    </div>

    <script>
        // Global state
        let currentKind = 'video';
        let playlistMode = 'video';
        let selectedVideoFormat = null;
        let selectedAudioFormat = null;
        let selectedSubtitle = '';
        let defaultDirs = { video: '', audio: '', subtitle: '' };
        let lastAutoSaveDir = '';
        let isBusy = false;

        // Utility functions
        function _shortCodec(codec) {
            if (!codec) return '';
            const parts = codec.split('.');
            const base = parts[0].split('-')[0];
            const short = {
                'h264': 'H.264', 'hevc': 'H.265', 'vp9': 'VP9',
                'av01': 'AV1', 'aac': 'AAC', 'opus': 'Opus',
                'vorbis': 'Vorbis', 'mp3': 'MP3', 'ac3': 'AC-3',
            };
            return short[base] || base.toUpperCase();
        }

        function _fmtSize(bytes) {
            if (!bytes) return '-';
            const units = ['B', 'KB', 'MB', 'GB'];
            let size = bytes;
            let unitIdx = 0;
            while (size >= 1024 && unitIdx < units.length - 1) {
                size /= 1024;
                unitIdx++;
            }
            return size.toFixed(1) + units[unitIdx];
        }

        function setBusy(busy) {
            isBusy = busy;
            document.getElementById('busyOverlay').classList.toggle('active', busy);
            document.querySelectorAll('.btn').forEach(btn => {
                btn.disabled = busy;
            });
            document.querySelectorAll('input[type="text"]').forEach(input => {
                input.disabled = busy;
            });
        }

        function appendLog(msg) {
            const logView = document.getElementById('logView');
            logView.textContent += msg + '\\n';
            logView.scrollTop = logView.scrollHeight;
        }

        function clearLog() {
            document.getElementById('logView').textContent = '';
        }

        function _setSaveDirDefault() {
            if (!defaultDirs.video) return;
            const saveDirInput = document.getElementById('saveDir');
            const next = currentKind === 'audio'
                ? defaultDirs.audio
                : currentKind === 'subtitle'
                    ? defaultDirs.subtitle
                    : defaultDirs.video;
            if (!saveDirInput.value || saveDirInput.value === lastAutoSaveDir) {
                saveDirInput.value = next;
                lastAutoSaveDir = next;
            }
        }

        function _togglePlaylistMode() {
            document.getElementById('playlistModeSection').style.display =
                currentKind === 'playlist' ? 'block' : 'none';
        }

        function _setActiveFormatPane(paneId) {
            document.querySelectorAll('.format-tab').forEach(t => t.classList.remove('active'));
            document.querySelectorAll('.format-pane').forEach(p => p.classList.remove('active'));
            const tab = document.querySelector(`.format-tab[data-pane="${paneId}"]`);
            const pane = document.getElementById(paneId);
            if (tab) tab.classList.add('active');
            if (pane) pane.classList.add('active');
        }

        function _syncKindUI() {
            _togglePlaylistMode();
            _setSaveDirDefault();
            if (currentKind === 'audio') {
                _setActiveFormatPane('audioPane');
            } else if (currentKind === 'subtitle') {
                _setActiveFormatPane('subtitlePane');
            } else {
                _setActiveFormatPane('videoPane');
            }
        }

        function _fmtVideoResolution(fmt) {
            if (fmt.resolution) return fmt.resolution;
            if (fmt.height) return `${fmt.height}p`;
            return '-';
        }

        function _fmtBitrate(value) {
            if (!value) return '-';
            return `${Math.round(value)} kbps`;
        }

        // Segmented control handlers
        document.querySelectorAll('#kind .btn').forEach(btn => {
            btn.addEventListener('click', () => {
                document.querySelectorAll('#kind .btn').forEach(b => b.classList.remove('selected'));
                btn.classList.add('selected');
                currentKind = btn.getAttribute('data-value');
                _syncKindUI();
            });
        });

        document.querySelectorAll('#playlistMode .btn').forEach(btn => {
            btn.addEventListener('click', () => {
                document.querySelectorAll('#playlistMode .btn').forEach(b => b.classList.remove('selected'));
                btn.classList.add('selected');
                playlistMode = btn.getAttribute('data-value');
            });
        });

        // Format tab handlers
        document.querySelectorAll('.format-tab').forEach(tab => {
            tab.addEventListener('click', () => {
                _setActiveFormatPane(tab.getAttribute('data-pane'));
            });
        });

        // API call handlers
        async function checkEnvironment() {
            setBusy(true);
            clearLog();
            try {
                appendLog('检查运行环境...');
                const result = await window.pywebview.api.check_environment();
                appendLog('环境检查完成');
                const items = Array.isArray(result.items) ? result.items : [];
                const pythonItem = items.find(item => item.name === 'python');
                const ytdlpItem = items.find(item => item.name === 'yt-dlp');
                const ffmpegItem = items.find(item => item.name === 'ffmpeg');
                if (result.ok) {
                    document.getElementById('envStatus').textContent = ffmpegItem && !ffmpegItem.found
                        ? '✓ 基本就绪'
                        : '✓ 就绪';
                    appendLog('✓ python: ' + (pythonItem && pythonItem.path ? pythonItem.path : '可用'));
                    appendLog('✓ yt-dlp: ' + (ytdlpItem && ytdlpItem.path ? ytdlpItem.path : '可用'));
                    if (ffmpegItem && ffmpegItem.found) {
                        appendLog('✓ ffmpeg: ' + (ffmpegItem.path || '可用'));
                    } else if (ffmpegItem) {
                        appendLog('⚠ ffmpeg: 缺失（可选）');
                    }
                } else {
                    document.getElementById('envStatus').textContent = '⚠ 缺失';
                    const missing = items.filter(item => item.required && !item.found);
                    if (missing.length === 0) {
                        appendLog('错误: 环境检查失败');
                    } else {
                        missing.forEach(item => {
                            appendLog(`⚠ ${item.name}: 缺失`);
                        });
                    }
                }
            } catch (e) {
                appendLog('错误: ' + e.message);
            } finally {
                setBusy(false);
            }
        }

        async function detectFormats() {
            const url = document.getElementById('url').value;
            if (!url) {
                appendLog('错误: URL 不能为空');
                return;
            }
            setBusy(true);
            clearLog();
            try {
                appendLog('探测格式...');
                const cookies = document.getElementById('cookies').value.trim();
                const result = await window.pywebview.api.detect_formats(url, cookies || null);
                if (result.error) {
                    appendLog('错误: ' + result.error);
                    return;
                }
                appendLog('探测完成: ' + result.title);
                document.getElementById('detectStatus').textContent = '✓ ' + result.title;
                selectedVideoFormat = null;
                selectedAudioFormat = null;
                selectedSubtitle = '';

                // Populate video formats
                const videoTable = document.getElementById('videoTable');
                videoTable.innerHTML = '';
                if (result.video_formats && result.video_formats.length > 0) {
                    result.video_formats.forEach(fmt => {
                        const formatId = fmt.format_id || fmt.id || '';
                        const bitrate = fmt.bitrate || _fmtBitrate(fmt.tbr);
                        const codec = fmt.video_codec || fmt.codec || '';
                        const filesize = fmt.filesize || fmt.filesize_approx || 0;
                        const row = document.createElement('tr');
                        row.dataset.formatId = formatId;
                        row.innerHTML = `
                            <td>${formatId || '-'}</td>
                            <td>${_fmtVideoResolution(fmt)}</td>
                            <td>${fmt.fps || '-'}</td>
                            <td>${bitrate || '-'}</td>
                            <td>${_shortCodec(codec)}</td>
                            <td>${fmt.ext || '-'}</td>
                            <td>${_fmtSize(filesize)}</td>
                            <td>${fmt.note || '-'}</td>
                        `;
                        row.addEventListener('click', () => {
                            document.querySelectorAll('#videoTable tr').forEach(r => r.classList.remove('selected'));
                            row.classList.add('selected');
                            selectedVideoFormat = formatId;
                        });
                        videoTable.appendChild(row);
                        if (!selectedVideoFormat && formatId) {
                            row.classList.add('selected');
                            selectedVideoFormat = formatId;
                        }
                    });
                }

                // Populate audio formats
                const audioTable = document.getElementById('audioTable');
                audioTable.innerHTML = '';
                if (result.audio_formats && result.audio_formats.length > 0) {
                    result.audio_formats.forEach(fmt => {
                        const formatId = fmt.format_id || fmt.id || '';
                        const bitrate = fmt.bitrate || _fmtBitrate(fmt.abr);
                        const codec = fmt.audio_codec || fmt.codec || '';
                        const channels = fmt.channels || (fmt.audio_channels ? `${fmt.audio_channels}ch` : '-');
                        const filesize = fmt.filesize || fmt.filesize_approx || 0;
                        const row = document.createElement('tr');
                        row.dataset.formatId = formatId;
                        row.innerHTML = `
                            <td>${formatId || '-'}</td>
                            <td>${bitrate || '-'}</td>
                            <td>${_shortCodec(codec)}</td>
                            <td>${fmt.ext || '-'}</td>
                            <td>${channels}</td>
                            <td>${_fmtSize(filesize)}</td>
                        `;
                        row.addEventListener('click', () => {
                            document.querySelectorAll('#audioTable tr').forEach(r => r.classList.remove('selected'));
                            row.classList.add('selected');
                            selectedAudioFormat = formatId;
                        });
                        audioTable.appendChild(row);
                        if (!selectedAudioFormat && formatId) {
                            row.classList.add('selected');
                            selectedAudioFormat = formatId;
                        }
                    });
                }

                // Populate subtitles
                const subtitleList = document.getElementById('subtitleList');
                subtitleList.innerHTML = '';
                const allSubs = [
                    ...(result.subtitles || []).map(sub => ({ ...sub, _isAuto: false })),
                    ...(result.auto_subtitles || []).map(sub => ({ ...sub, _isAuto: true })),
                ];
                if (allSubs.length > 0) {
                    allSubs.forEach(sub => {
                        const item = document.createElement('div');
                        item.className = 'subtitle-item';
                        const isAuto = !!sub._isAuto;
                        const value = isAuto ? `auto:${sub.lang}` : sub.lang;
                        const left = document.createElement('span');
                        const lang = document.createElement('span');
                        lang.className = 'subtitle-lang';
                        lang.textContent = sub.lang;
                        const auto = document.createElement('span');
                        auto.className = 'subtitle-auto';
                        auto.textContent = isAuto ? '(自动)' : '';
                        left.appendChild(lang);
                        left.appendChild(document.createTextNode(' '));
                        left.appendChild(auto);
                        const meta = document.createElement('span');
                        meta.className = 'subtitle-auto';
                        meta.textContent = sub.label || sub.ext || '-';
                        item.appendChild(left);
                        item.appendChild(meta);
                        item.addEventListener('click', () => {
                            document.querySelectorAll('#subtitleList .subtitle-item').forEach(el => el.classList.remove('selected'));
                            item.classList.add('selected');
                            selectedSubtitle = value;
                        });
                        subtitleList.appendChild(item);
                        if (!selectedSubtitle) {
                            item.classList.add('selected');
                            selectedSubtitle = value;
                        }
                    });
                }

                document.getElementById('formatCard').style.display = 'block';
            } catch (e) {
                appendLog('错误: ' + e.message);
            } finally {
                setBusy(false);
            }
        }

        async function startDownload() {
            const url = document.getElementById('url').value;
            const destDir = document.getElementById('saveDir').value;
            if (!url) {
                appendLog('错误: URL 不能为空');
                return;
            }
            if (!destDir) {
                appendLog('错误: 保存目录不能为空');
                return;
            }
            if (currentKind === 'video' && !selectedVideoFormat) {
                appendLog('错误: 请先探测并选择视频格式');
                return;
            }
            if (currentKind === 'audio' && !selectedAudioFormat) {
                appendLog('错误: 请先探测并选择音频格式');
                return;
            }
            if (currentKind === 'subtitle' && !selectedSubtitle) {
                appendLog('错误: 请先探测并选择字幕');
                return;
            }
            setBusy(true);
            clearLog();
            try {
                appendLog('开始下载...');
                let extraArgs = document.getElementById('extraArgs').value.split(/\\s+/).filter(Boolean);
                const cookies = document.getElementById('cookies').value.trim();
                if (currentKind === 'playlist') {
                    extraArgs = extraArgs.filter(arg => arg !== '--no-playlist');
                } else if (!extraArgs.includes('--no-playlist')) {
                    extraArgs.push('--no-playlist');
                }
                const primaryFormatId = currentKind === 'playlist'
                    ? playlistMode
                    : currentKind === 'audio'
                        ? (selectedAudioFormat || '')
                        : currentKind === 'subtitle'
                            ? ''
                            : (selectedVideoFormat || '');
                const result = await window.pywebview.api.start_download(
                    currentKind,
                    url,
                    destDir,
                    primaryFormatId,
                    currentKind === 'video' ? (selectedAudioFormat || '') : '',
                    currentKind === 'subtitle' ? selectedSubtitle : '',
                    document.getElementById('transcode').value,
                    cookies || null,
                    extraArgs
                );
                if (result.error) {
                    appendLog('错误: ' + result.error);
                } else {
                    appendLog(result.output || '下载完成');
                    if (result.saved_path) {
                        appendLog('保存到: ' + result.saved_path);
                    }
                }
            } catch (e) {
                appendLog('错误: ' + e.message);
            } finally {
                setBusy(false);
            }
        }

        async function browseSaveDir() {
            try {
                const dir = await window.pywebview.api.browse_directory(
                    document.getElementById('saveDir').value
                );
                if (dir) {
                    document.getElementById('saveDir').value = dir;
                    lastAutoSaveDir = '';
                }
            } catch (e) {
                appendLog('错误: ' + e.message);
            }
        }

        // Progress callback from Python
        window._onProgress = function(message) {
            appendLog(message);
        };

        // Initialize on load
        async function initialize() {
            try {
                const dirs = await window.pywebview.api.get_default_dirs();
                defaultDirs = dirs;
                _syncKindUI();
            } catch (e) {
                console.error('Failed to get default dirs:', e);
            }
        }

        // Keyboard shortcuts
        document.addEventListener('keydown', e => {
            if (e.key === 'Enter' && !isBusy && e.ctrlKey) {
                startDownload();
            }
        });

        window.addEventListener('load', initialize);
    </script>
</body>
</html>
"""
