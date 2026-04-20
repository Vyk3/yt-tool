import Foundation

/// Parses yt-dlp `--progress --newline` stderr lines into DownloadProgress values.
///
/// A typical progress line looks like:
///   [download]  25.3% of    6.48MiB at    1.24MiB/s ETA 00:03
struct ProgressParser {
    // Matches: [download]  <percent>% of <size> at <speed> ETA <eta>
    // Also handles: [download]  <percent>% of <size> in <elapsed> (no ETA when complete)
    // nonisolated(unsafe) is required for Swift 6: Regex<> is not Sendable but the value
    // is effectively immutable after init, so shared access is safe.
    nonisolated(unsafe) private static let percentPattern = #/\[download\]\s+([\d.]+)%/#

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

    /// Processes a raw stderr chunk (may contain multiple lines) and returns
    /// the last meaningful DownloadProgress found, if any.
    func parse(chunk: String) -> DownloadProgress? {
        let lines = chunk.components(separatedBy: "\n")
        return lines.compactMap { parse(line: $0) }.last
    }
}
