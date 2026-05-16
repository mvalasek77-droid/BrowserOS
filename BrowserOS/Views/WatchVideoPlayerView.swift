import SwiftUI
import AVFoundation

// MARK: - Watch Video Player
// Full-featured video player for watchOS using AVPlayer

struct WatchVideoPlayerView: View {
    @StateObject private var viewModel = VideoPlayerViewModel()
    @State private var showControls = true
    @State private var showQualityPicker = false
    @Environment(\.dismiss) var dismiss
    
    let mediaItem: MediaItem
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Video rendering area
                // On watchOS 10+, we can display video via AVPlayerControllerRepresentable
                WatchOSVideoRenderer(player: viewModel.player)
                    .frame(maxWidth: .infinity)
                    .frame(height: 130)
                    .clipped()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showControls.toggle()
                        }
                    }
                
                Spacer(minLength: 0)
                
                if showControls {
                    controlsOverlay
                        .transition(.opacity)
                }
                
                if let error = viewModel.errorMessage {
                    errorOverlay(error)
                }
                
                if viewModel.isBuffering && viewModel.errorMessage == nil {
                    loadingOverlay
                }
            }
        }
        .overlay {
            if showQualityPicker {
                QualityPickerSheet(
                    qualities: viewModel.availableQualities,
                    current: viewModel.currentQuality,
                    onSelect: { stream in
                        viewModel.changeQuality(stream)
                        showQualityPicker = false
                    },
                    onDismiss: { showQualityPicker = false }
                )
            }
        }
        .onAppear { loadMedia() }
        .onDisappear { viewModel.player?.pause() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Image(systemName: "xmark") }
            }
        }
    }
    
    // MARK: - Controls Overlay
    
    private var controlsOverlay: some View {
        VStack(spacing: 6) {
            // Title
            Text(mediaItem.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
            
            // Time row
            HStack {
                Text(formatTime(viewModel.currentTime))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(formatTime(viewModel.duration))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 12)
            
            // Scrubber — Digital Crown controlled
            VideoScrubberView(
                currentTime: Binding(
                    get: { viewModel.currentTime },
                    set: { viewModel.seek(to: $0) }
                ),
                duration: viewModel.duration,
                bufferProgress: viewModel.bufferProgress,
                onSeek: { time in viewModel.seek(to: time) }
            )
            .padding(.horizontal, 8)
            .focusable(true)
            .digitalCrownRotation(
                Binding(
                    get: { viewModel.currentTime },
                    set: { viewModel.seek(to: $0) }
                ),
                from: 0,
                through: max(viewModel.duration, 1),
                by: 5,
                sensitivity: .medium,
                isHapticFeedbackEnabled: true
            )
            
            // Transport controls
            HStack(spacing: 20) {
                Button { viewModel.seekRelative(-15) } label: {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                }.buttonStyle(.plain)
                
                Button { viewModel.togglePlayback() } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                }.buttonStyle(.plain)
                
                Button { viewModel.seekRelative(15) } label: {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                }.buttonStyle(.plain)
            }
            .padding(.vertical, 4)
            
            // Bottom row
            HStack {
                if !viewModel.availableQualities.isEmpty {
                    Button { showQualityPicker = true } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "slider.horizontal.3").font(.system(size: 9))
                            Text(viewModel.currentQuality).font(.system(size: 9))
                        }
                        .foregroundStyle(.white.opacity(0.7))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Button { viewModel.toggleMute() } label: {
                    Image(systemName: viewModel.volume > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.85))
    }
    
    // MARK: - Error Overlay
    
    private func errorOverlay(_ error: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title3)
                .foregroundStyle(.orange)
            Text(error)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            Button("Retry") { loadMedia() }
                .buttonStyle(.bordered)
                .controlSize(.mini)
        }
        .padding()
    }
    
    // MARK: - Loading Overlay
    
    private var loadingOverlay: some View {
        VStack(spacing: 6) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
            Text("Loading...")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Media Loading
    
    private func loadMedia() {
        switch mediaItem.source {
        case .youtube:
            if let streamURL = mediaItem.streamURL,
               let videoID = extractYouTubeID(from: streamURL) {
                Task { await viewModel.playYouTube(videoID: videoID) }
            }
        case .direct, .vimeo, .dailymotion, .other:
            if let streamURL = mediaItem.streamURL,
               let url = URL(string: streamURL) {
                viewModel.play(url: url)
            }
        case .netflix:
            openInNetflixApp()
        }
    }
    
    private func extractYouTubeID(from url: String) -> String? {
        let patterns = [
            #"v=([a-zA-Z0-9_-]{11})"#,
            #"youtu\.be/([a-zA-Z0-9_-]{11})"#,
            #"embed/([a-zA-Z0-9_-]{11})"#,
            #"shorts/([a-zA-Z0-9_-]{11})"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)),
               let range = Range(match.range(at: 1), in: url) {
                return String(url[range])
            }
        }
        return nil
    }
    
    private func openInNetflixApp() {
        if let url = URL(string: "nflx://") {
            #if os(iOS)
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else {
                viewModel.errorMessage = "Install the Netflix app to watch content"
            }
            #else
            // On watchOS, use Handoff to open on iPhone instead
            let activity = NSUserActivity(activityType: "com.browseros.netflix")
            activity.webpageURL = URL(string: mediaItem.pageURL)
            activity.title = "Watch on Netflix"
            activity.userInfo = ["url": mediaItem.pageURL]
            activity.becomeCurrent()
            viewModel.errorMessage = "Use Handoff to open on iPhone"
            #endif
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = Int(max(0, seconds))
        let hrs = totalSeconds / 3600
        let mins = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }
}

// Video renderer is in VideoRenderer.swift