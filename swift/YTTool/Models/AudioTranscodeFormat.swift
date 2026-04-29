import Foundation

enum AudioTranscodeFormat: String, CaseIterable, Identifiable {
    case original
    case mp3
    case m4a
    case wav

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Keep original"
        case .mp3: return "MP3"
        case .m4a: return "M4A"
        case .wav: return "WAV"
        }
    }

    var ytDlpAudioFormat: String? {
        switch self {
        case .original: return nil
        case .mp3: return "mp3"
        case .m4a: return "m4a"
        case .wav: return "wav"
        }
    }
}
