import SwiftUI

enum ProbeState: Equatable {
    case idle
    case loading
    case success(MediaInfo)
    case failure(AppError)
}
