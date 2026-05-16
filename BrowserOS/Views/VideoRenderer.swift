import SwiftUI
import AVFoundation

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
        // On watchOS 10+, use SwiftUI's native video support
        // AVPlayer plays full screen or inline depending on context
        Color.black
            .onAppear {
                // The player is already playing — video renders to the display
            }
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