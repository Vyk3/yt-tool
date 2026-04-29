import Foundation

func isYouTubeURL(_ url: String) -> Bool {
    guard let host = URLComponents(string: url)?.host?.lowercased() else { return false }
    return host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be"
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
    extraArguments: [String] = []
) -> [String] {
    var args = [
        "-f", formatSelector,
        "-o", outputTemplate,
        "--ffmpeg-location", ffmpegLocation,
        "--print", "after_move:filepath",
        "--progress",
        "--newline",
    ]
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
            "--concurrent-fragments", "4",
            "--embed-thumbnail",
            "--embed-chapters",
            "--embed-metadata",
        ]
    }
    args.append(url)
    return args
}

func parseShellLikeArguments(_ input: String) throws -> [String] {
    enum ParseError: Error { case unterminatedQuote(Character) }

    var args: [String] = []
    var current = ""
    var quote: Character?
    var escaping = false

    func flushCurrent() {
        if !current.isEmpty {
            args.append(current)
            current = ""
        }
    }

    for ch in input {
        if escaping {
            current.append(ch)
            escaping = false
            continue
        }
        if ch == "\\" {
            escaping = true
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
            continue
        }
        if ch.isWhitespace {
            flushCurrent()
            continue
        }
        current.append(ch)
    }
    if let quote {
        throw ParseError.unterminatedQuote(quote)
    }
    flushCurrent()
    return args
}
