import Foundation

// MARK: - Option Schema

enum OptionContext {
    case probe
    case download
}

enum ExtraOptionName: String, CaseIterable, Equatable {
    case proxy = "--proxy"
    case forceIPv4 = "--force-ipv4"
    case forceIPv6 = "--force-ipv6"
    case retries = "--retries"
    case limitRate = "--limit-rate"
    case fragmentRetries = "--fragment-retries"
    case sleepInterval = "--sleep-interval"
    case maxSleepInterval = "--max-sleep-interval"
    case mergeOutputFormat = "--merge-output-format"
    case downloadSections = "--download-sections"
    case subFormat = "--sub-format"
    case restrictFilenames = "--restrict-filenames"
    case noMtime = "--no-mtime"
    case noOverwrites = "--no-overwrites"
    case noPart = "--no-part"
    case ignoreErrors = "--ignore-errors"
    case noAbortOnError = "--no-abort-on-error"
    case bufferSize = "--buffer-size"

    enum Arity { case flag, value }

    var arity: Arity {
        switch self {
        case .proxy, .retries, .limitRate, .fragmentRetries,
             .sleepInterval, .maxSleepInterval, .mergeOutputFormat,
             .downloadSections, .subFormat, .bufferSize:
            .value
        case .forceIPv4, .forceIPv6, .restrictFilenames, .noMtime,
             .noOverwrites, .noPart, .ignoreErrors, .noAbortOnError:
            .flag
        }
    }

    var context: OptionContext {
        switch self {
        case .proxy, .forceIPv4, .forceIPv6, .retries:
            .probe
        default:
            .download
        }
    }

    var allowsRepeat: Bool {
        self == .downloadSections
    }

    func validate(_ value: String) -> Bool {
        switch self {
        case .proxy:
            ExtraOptionValidation.isHTTPProxyURL(value)
        case .retries, .fragmentRetries:
            value == "infinite" || ExtraOptionValidation.isNonNegativeInt(value)
        case .limitRate, .bufferSize:
            ExtraOptionValidation.isRateLiteral(value)
        case .sleepInterval, .maxSleepInterval:
            ExtraOptionValidation.isFiniteNonNegativeDouble(value)
        case .mergeOutputFormat:
            ["mp4", "mkv", "webm"].contains(value)
        case .downloadSections:
            ExtraOptionValidation.isValidDownloadSection(value)
        case .subFormat:
            !value.isEmpty
        case .forceIPv4, .forceIPv6, .restrictFilenames, .noMtime,
             .noOverwrites, .noPart, .ignoreErrors, .noAbortOnError:
            true
        }
    }

    var passesToProbe: Bool {
        context == .probe
    }

    var passesToDownload: Bool {
        true
    }
}

struct ParsedExtraOption: Equatable {
    let name: ExtraOptionName
    let value: String?
}

enum ExtraOptionValidation {
    static func isNonNegativeInt(_ s: String) -> Bool {
        guard let v = Int(s) else { return false }
        return v >= 0
    }

    static func isFiniteNonNegativeDouble(_ s: String) -> Bool {
        guard let v = Double(s) else { return false }
        return v >= 0 && v.isFinite
    }

    static func isRateLiteral(_ s: String) -> Bool {
        let pattern = #"^\d+[KMG]?$"#
        return s.range(of: pattern, options: .regularExpression) != nil
    }

    static func isHTTPProxyURL(_ s: String) -> Bool {
        guard let url = URL(string: s),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return false }
        if url.user != nil || url.password != nil { return false }
        if let port = url.port, port < 1 || port > 65535 { return false }
        return true
    }

    static func isValidDownloadSection(_ s: String) -> Bool {
        let pattern = #"^\*(\d{1,2}):(\d{2}):(\d{2})-(\d{1,2}):(\d{2}):(\d{2})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              match.numberOfRanges == 7
        else {
            return false
        }
        func capture(_ i: Int) -> Int {
            Int(s[Range(match.range(at: i), in: s)!])!
        }
        let sh = capture(1), sm = capture(2), ss = capture(3)
        let eh = capture(4), em = capture(5), es = capture(6)
        guard sm < 60, ss < 60, em < 60, es < 60 else { return false }
        let startTotal = sh * 3600 + sm * 60 + ss
        let endTotal = eh * 3600 + em * 60 + es
        return endTotal > startTotal
    }
}

enum OptionParseError: LocalizedError, Equatable {
    case unknownOption(String)
    case shortOption(String)
    case doubleDashSeparator
    case missingValue(ExtraOptionName)
    case flagWithValue(ExtraOptionName)
    case duplicateOption(ExtraOptionName)
    case invalidValue(ExtraOptionName, String)
    case mutuallyExclusive(ExtraOptionName, ExtraOptionName)
    case barePositional(String)
    case shellParseError(String)

    var errorDescription: String? {
        switch self {
        case let .unknownOption(opt):
            "Unknown option: \(opt). Only allowlisted options are accepted."
        case let .shortOption(opt):
            "Short options are not allowed: \(opt)"
        case .doubleDashSeparator:
            "The -- separator is not allowed."
        case let .missingValue(opt):
            "\(opt.rawValue) requires a value."
        case let .flagWithValue(opt):
            "\(opt.rawValue) is a flag and does not accept a value."
        case let .duplicateOption(opt):
            "\(opt.rawValue) cannot be specified more than once."
        case let .invalidValue(opt, val):
            "Invalid value for \(opt.rawValue): \(val)"
        case let .mutuallyExclusive(a, b):
            "\(a.rawValue) and \(b.rawValue) cannot be used together."
        case let .barePositional(token):
            "Unexpected argument: \(token)"
        case let .shellParseError(msg):
            msg
        }
    }
}

func parseExtraOptions(_ input: String) throws -> [ParsedExtraOption] {
    let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else { return [] }

    let tokens: [String]
    do {
        tokens = try parseShellLikeArguments(raw)
    } catch {
        throw OptionParseError.shellParseError(error.localizedDescription)
    }

    var result: [ParsedExtraOption] = []
    var seen = Set<ExtraOptionName>()
    var i = 0

    while i < tokens.count {
        let token = tokens[i]

        if token == "--" {
            throw OptionParseError.doubleDashSeparator
        }

        guard token.hasPrefix("-") else {
            throw OptionParseError.barePositional(token)
        }

        if token.hasPrefix("-"), !token.hasPrefix("--") {
            throw OptionParseError.shortOption(token)
        }

        var optionName: String
        var inlineValue: String?

        if let eqIndex = token.firstIndex(of: "=") {
            optionName = String(token[..<eqIndex])
            inlineValue = String(token[token.index(after: eqIndex)...])
        } else {
            optionName = token
            inlineValue = nil
        }

        guard let name = ExtraOptionName(rawValue: optionName) else {
            throw OptionParseError.unknownOption(optionName)
        }

        switch name.arity {
        case .flag:
            if inlineValue != nil {
                throw OptionParseError.flagWithValue(name)
            }
            if seen.contains(name), !name.allowsRepeat {
                throw OptionParseError.duplicateOption(name)
            }
            seen.insert(name)
            result.append(ParsedExtraOption(name: name, value: nil))
            i += 1

        case .value:
            let value: String
            if let inline = inlineValue {
                value = inline
            } else {
                guard i + 1 < tokens.count else {
                    throw OptionParseError.missingValue(name)
                }
                i += 1
                value = tokens[i]
            }
            if !name.allowsRepeat, seen.contains(name) {
                throw OptionParseError.duplicateOption(name)
            }
            guard name.validate(value) else {
                throw OptionParseError.invalidValue(name, value)
            }
            seen.insert(name)
            result.append(ParsedExtraOption(name: name, value: value))
            i += 1
        }
    }

    if seen.contains(.forceIPv4), seen.contains(.forceIPv6) {
        throw OptionParseError.mutuallyExclusive(.forceIPv4, .forceIPv6)
    }

    return result
}

func renderExtraOptions(_ options: [ParsedExtraOption], for context: OptionContext) -> [String] {
    var result: [String] = []
    for option in options {
        let include = switch context {
        case .probe: option.name.passesToProbe
        case .download: option.name.passesToDownload
        }
        guard include else { continue }
        result.append(option.name.rawValue)
        if let value = option.value {
            result.append(value)
        }
    }
    return result
}

// MARK: - URL Helpers

func isYouTubeURL(_ url: String) -> Bool {
    guard let host = URLComponents(string: url)?.host?.lowercased() else { return false }
    return host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be"
}

private let supportedVideoHosts: [String] = [
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
    buildProbeArguments(url: url, cookiesFilePath: nil, extraOptions: [])
}

func buildProbeArguments(
    url: String,
    cookiesFilePath: String?,
    extraOptions: [ParsedExtraOption]
) -> [String] {
    var args = ["--dump-single-json", "--no-playlist"]
    if let cookiesFilePath, !cookiesFilePath.isEmpty {
        args += ["--cookies", cookiesFilePath]
    }
    args += renderExtraOptions(extraOptions, for: .probe)
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
    extraOptions: [ParsedExtraOption] = [],
    managedArguments: [String] = [],
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
            "--downloader", "m3u8:native",
            "--downloader-args", "aria2c:-x 16 -s 16 -k 1M",
            "-N", "4",
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
    args += renderExtraOptions(extraOptions, for: .download)
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
        if aria2cPath == nil {
            args += ["--concurrent-fragments", "4"]
        }
    }
    args += managedArguments
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
