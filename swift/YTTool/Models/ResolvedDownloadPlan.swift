import Foundation

struct ResolvedDownloadPlan: Equatable {
    let url: String
    let formatSelector: String
    let includeNoPlaylist: Bool
    let audioTranscodeFormat: AudioTranscodeFormat?
    let cookiesFilePath: String?
    let extraOptions: [ParsedExtraOption]
    let managedArguments: [String]
    let selectedProtocols: [String?]
    let subtitleTrack: SubtitleTrack?
    let outputDirectory: URL
    let aria2cPath: String?
    let previewTarget: String
    let returnsOutputDirectoryOnSuccess: Bool

    var outputTemplate: String {
        outputDirectory
            .appendingPathComponent("%(title)s [%(resolution)s].%(ext)s")
            .path(percentEncoded: false)
    }
}
