import SwiftUI

// MARK: - MediaSource SwiftUI Extensions
// These need SwiftUI so they're in a separate file from the Foundation-only SharedModels

extension MediaSource {
    var icon: String { iconName }
    
    var color: Color {
        switch self {
        case .youtube: return .red
        case .vimeo: return .cyan
        case .dailymotion: return .blue
        case .direct: return .purple
        case .netflix: return .red
        case .other: return .gray
        }
    }
}