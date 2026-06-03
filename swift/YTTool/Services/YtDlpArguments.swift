import Foundation

func isYouTubeURL(_ url: String) -> Bool {
    guard let host = URLComponents(string: url)?.host?.lowercased() else { return false }
    return host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be"
}

private let supportedVideoHosts: Set<String> = [
    "youtube.com", "youtu.be",
    "bilibili.com", "b23.tv",
    "vimeo.com",
    "dailymotion.com", "dai.ly",
    "twitter.com", "x.com",
    "tiktok.com",
    "twitch.tv",
    "soundcloud.com",
    "facebook.com", "fb.watch",
    "instagram.com",
    "reddit.com",
    "nicovideo.jp",
    "crunchyroll.com",
    "bandcamp.com",
    "mixcloud.com",
    "streamable.com",
    "rumble.com",
    "odysee.com",
    "bitchute.com",
    "pinterest.com",
    "ted.com",
    "abema.tv",
    "weibo.com",
    "douyin.com",
    "kuaishou.com",
    "ixigua.com",
    "xiaohongshu.com",
]

/// Hosts that look like a supported video platform but are
/// channel/user pages, not downloadable video URLs.
private let nonVideoSubdomains: Set<String> = [
    "space.bilibili.com",
]

func isSupportedVideoHost(_ url: String) -> Bool {
    guard let host = URLComponents(string: url)?.host?.lowercased() else { return false }
    if nonVideoSubdomains.contains(host) { return false }
    return supportedVideoHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
}

func buildProbeArguments(url: String) -> [String] {
    buildProbeArguments(url: url, cookiesFilePath: nil, extraArguments: [])
}

func buildProbeArguments(
    url: String,
    cookiesFilePath: String?,
    extraArguments: [String]
) -> [String] {
    var args = ["--dump-single-json", "--no-playlist"]
    if let cookiesFilePath, !cookiesFilePath.isEmpty {
        args += ["--cookies", cookiesFilePath]
    }
    args += extraArguments
    if isYouTubeURL(url) { args += ["--extractor-args", "youtube:player_client=default"] }
    args.append(url)
    return args
}

func buildDownloadArguments(
    url: String,
    formatSelector: String,
    outputTemplate: String,
    ffmpegLocation: String,
    subtitleTrack: SubtitleTrack? = nil,
    includeNoPlaylist: Bool = true,
    audioTranscodeFormat: AudioTranscodeFormat? = nil,
    cookiesFilePath: String? = nil,
    extraArguments: [String] = [],
    aria2cPath: String? = nil
) -> [String] {
    var args = [
        "-f", formatSelector,
        "-o", outputTemplate,
        "--ffmpeg-location", ffmpegLocation,
        "--print", "after_move:filepath",
        "--progress",
        "--newline",
    ]
    if let aria2cPath {
        args += [
            "--downloader", aria2cPath,
            "--downloader-args", "aria2c:-x 16 -s 16 -k 1M",
        ]
    }
    if let cookiesFilePath, !cookiesFilePath.isEmpty {
        args += ["--cookies", cookiesFilePath]
    }
    if includeNoPlaylist { args.append("--no-playlist") }
    if let subtitleTrack {
        args += [subtitleTrack.isAuto ? "--write-auto-subs" : "--write-subs", "--sub-langs", subtitleTrack.lang]
    }
    if let format = audioTranscodeFormat?.ytDlpAudioFormat {
        args += ["-x", "--audio-format", format]
    }
    args += extraArguments
    if isYouTubeURL(url) {
        if subtitleTrack?.isAuto == true {
            args += ["--sleep-subtitles", "60"]
        }
        args += [
            "--extractor-args", "youtube:player_client=default",
            "--embed-thumbnail",
            "--embed-chapters",
            "--embed-metadata",
        ]
        // aria2c handles its own multi-connection; --concurrent-fragments is redundant
        if aria2cPath == nil {
            args += ["--concurrent-fragments", "4"]
        }
    }
    args.append(url)
    return args
}

func parseShellLikeArguments(_ input: String) throws -> [String] {
    enum ParseError: LocalizedError {
        case unterminatedQuote(Character)
        case danglingEscape

        var errorDescription: String? {
            switch self {
            case let .unterminatedQuote(quote):
                "Unterminated quoted argument starting with \(quote)."
            case .danglingEscape:
                "Trailing backslash must escape a following character."
            }
        }
    }

    var args: [String] = []
    var current = ""
    var quote: Character?
    var escaping = false
    var tokenStarted = false

    func flushCurrent() {
        if tokenStarted || !current.isEmpty {
            args.append(current)
            current = ""
            tokenStarted = false
        }
    }

    for ch in input {
        if escaping {
            current.append(ch)
            escaping = false
            tokenStarted = true
            continue
        }
        if ch == "\\" {
            escaping = true
            tokenStarted = true
            continue
        }
        if let currentQuote = quote {
            if ch == currentQuote {
                quote = nil
            } else {
                current.append(ch)
            }
            continue
        }
        if ch == "\"" || ch == "'" {
            quote = ch
            tokenStarted = true
            continue
        }
        if ch.isWhitespace {
            flushCurrent()
            continue
        }
        current.append(ch)
        tokenStarted = true
    }
    if escaping {
        throw ParseError.danglingEscape
    }
    if let quote {
        throw ParseError.unterminatedQuote(quote)
    }
    flushCurrent()
    return args
}
