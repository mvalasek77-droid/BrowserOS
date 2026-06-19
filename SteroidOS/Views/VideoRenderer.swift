import SwiftUI
import AVFoundation
#if canImport(AVKit)
import AVKit
#endif

// MARK: - watchOS Video Renderer
// On watchOS, AVPlayer renders video. We provide a container.
// watchOS 10+ supports inline video playback natively in SwiftUI.

struct WatchOSVideoRenderer: View {
    let player: AVPlayer?
    
    var body: some View {
        ZStack {
            Color.black
            
            if let player = player {
                // On watchOS, the video player surface
                VideoSurface(player: player)
            } else {
                Image(systemName: "play.rectangle")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.2))
            }
        }
    }
}

// MARK: - Video Surface
// Platform-specific video rendering bridge

#if os(watchOS)

struct VideoSurface: View {
    let player: AVPlayer
    
    var body: some View {
        // watchOS 10+ supports VideoPlayer natively in SwiftUI
        VideoPlayer(player: player)
            .disabled(false) // allow play/pause tap
    }
}

#else

struct VideoSurface: View {
    let player: AVPlayer
    
    var body: some View {
        Rectangle()
            .fill(Color.black)
            .overlay {
                Image(systemName: "play.rectangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.3))
            }
    }
}

#endif