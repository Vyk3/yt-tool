import Foundation

/// Parses yt-dlp `--progress --newline` stderr lines into DownloadProgress values.
///
/// A typical progress line looks like:
///   [download]  25.3% of    6.48MiB at    1.24MiB/s ETA 00:03
///
/// **Usage**: keep one `ProgressParser` instance per download and call
/// `parse(chunk:)` with every raw stderr chunk. The parser maintains an
/// internal line buffer so that progress lines split across pipe callbacks
/// are reconstructed correctly before matching.
struct ProgressParser {
    // nonisolated(unsafe) is required for Swift 6: Regex<> is not Sendable but the value
    // is effectively immutable after init, so shared access is safe.
    nonisolated(unsafe) private static let percentPattern = #/\[download\]\s+([\d.]+)%/#

    /// Incomplete text from the previous chunk that did not end with a newline.
    private var lineBuffer: String = ""

    /// Returns a DownloadProgress if the line is a recognized yt-dlp progress line,
    /// or nil if it is a non-progress stderr line (e.g. info/warning/error messages).
    func parse(line: String) -> DownloadProgress? {
        guard let match = try? ProgressParser.percentPattern.firstMatch(in: line) else {
            return nil
        }
        let percent = Double(match.1) ?? 0
        let summary = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[download]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return DownloadProgress(
            percentComplete: min(percent / 100.0, 1.0),
            summaryLine: summary
        )
    }

    /// Processes a raw stderr chunk, buffering any incomplete trailing line
    /// across calls so that pipe-split progress lines are parsed correctly.
    /// Returns the last meaningful DownloadProgress found in this chunk, if any.
    mutating func parse(chunk: String) -> DownloadProgress? {
        // Prepend any leftover fragment from the previous call.
        let text = lineBuffer + chunk

        // The last component after splitting on "\n" is either empty (chunk
        // ended with a newline) or an incomplete line to buffer for next time.
        var components = text.components(separatedBy: "\n")
        lineBuffer = components.removeLast()   // "" if chunk ended with \n

        return components.compactMap { parse(line: $0) }.last
    }
}
