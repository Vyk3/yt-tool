import Foundation

enum AudioTranscodeFormat: String, CaseIterable, Identifiable {
    case original
    case mp3
    case m4a
    case wav

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .original: "Keep original"
        case .mp3: "MP3"
        case .m4a: "M4A"
        case .wav: "WAV"
        }
    }

    var ytDlpAudioFormat: String? {
        switch self {
        case .original: nil
        case .mp3: "mp3"
        case .m4a: "m4a"
        case .wav: "wav"
        }
    }
}
