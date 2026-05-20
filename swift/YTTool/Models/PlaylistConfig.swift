/// Groups all playlist-related settings into a single value type.
///
/// Passed as one `@Binding` to views instead of 8 individual bindings,
/// and stored as one `@Published` property in `AppState`.
struct PlaylistConfig: Equatable {
    var mode: PlaylistMode = .onlyFirstItem
    var videoQualityStrategy: PlaylistVideoQualityStrategy = .bestCompatibility
    var audioQualityStrategy: PlaylistAudioQualityStrategy = .moreCompatible
    var subtitleMode: PlaylistSubtitleMode = .none
    var subtitleLanguage: String = ""
    var segmentMode: PlaylistSegmentMode = .fullItem
    var segmentRange: String = ""
    var formatMode: PlaylistFormatMode = .unifiedStrategy
    var perItemFormatMap: String = ""
}
