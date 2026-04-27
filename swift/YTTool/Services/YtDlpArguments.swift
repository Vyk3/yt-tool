import Foundation

func isYouTubeURL(_ url: String) -> Bool {
    guard let host = URLComponents(string: url)?.host?.lowercased() else { return false }
    return host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be"
}

func buildProbeArguments(url: String) -> [String] {
    var args = ["--dump-single-json", "--no-playlist"]
    if isYouTubeURL(url) { args += ["--extractor-args", "youtube:player_client=default"] }
    args.append(url)
    return args
}

func buildDownloadArguments(
    url: String,
    formatSelector: String,
    outputTemplate: String,
    ffmpegDirectory: String,
    includeNoPlaylist: Bool = true
) -> [String] {
    var args = [
        "-f", formatSelector,
        "-o", outputTemplate,
        "--ffmpeg-location", ffmpegDirectory,
        "--print", "after_move:filepath",
        "--progress",
        "--newline",
    ]
    if includeNoPlaylist { args.append("--no-playlist") }
    if isYouTubeURL(url) {
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
