import SwiftUI
import AVFoundation
import Combine

// MARK: - Video Player View Model

@MainActor
class VideoPlayerViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var bufferProgress: Double = 0
    @Published var isBuffering: Bool = false
    @Published var errorMessage: String? = nil
    @Published var availableQualities: [VideoStream] = []
    @Published var currentQuality: String = "Auto"
    @Published var volume: Float = 1.0
    
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    
    func play(url: URL) {
        removeTimeObserver()
        player?.pause()
        cancellables.removeAll()
        
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        
        // Observe item status
        item.publisher(for: \.status)
            .sink { [weak self] status in
                switch status {
                case .readyToPlay:
                    self?.isBuffering = false
                    self?.duration = item.duration.seconds
                case .failed:
                    self?.errorMessage = item.error?.localizedDescription ?? "Playback failed"
                    self?.isBuffering = false
                @unknown default:
                    break
                }
            }
            .store(in: &cancellables)
        
        // Buffer progress
        item.publisher(for: \.loadedTimeRanges)
            .sink { [weak self] ranges in
                guard let self = self, let range = ranges.first else { return }
                let bufferEnd = CMTimeGetSeconds(range.timeRangeValue.duration) + CMTimeGetSeconds(range.timeRangeValue.start)
                if self.duration > 0 {
                    self.bufferProgress = bufferEnd / self.duration
                }
            }
            .store(in: &cancellables)
        
        // Time observer
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }
        
        // Rate observer
        newPlayer.publisher(for: \.rate)
            .sink { [weak self] rate in
                self?.isPlaying = rate > 0
            }
            .store(in: &cancellables)
        
        player = newPlayer
        isBuffering = true
        errorMessage = nil
        newPlayer.volume = volume
        newPlayer.play()
    }
    
    func playYouTube(videoID: String) async {
        let detector = MediaDetector()
        let streams = await detector.extractYouTubeStreams(videoID: videoID)
        
        if streams.isEmpty {
            // Fallback: Invidious direct stream
            let fallbacks = [
                "https://inv.nadeko.net/latest_version?id=\(videoID)&local=true",
                "https://invidious.nerdvpn.de/latest_version?id=\(videoID)&local=true"
            ]
            for fallback in fallbacks {
                if let url = URL(string: fallback) {
                    play(url: url)
                    return
                }
            }
            errorMessage = "Could not extract video stream"
            return
        }
        
        availableQualities = streams
        
        // Pick 480p for watch performance, fallback to first available
        let bestStream = streams.first(where: { $0.quality.contains("480") })
            ?? streams.first(where: { $0.quality.contains("360") })
            ?? streams.first
        
        if let stream = bestStream {
            currentQuality = stream.quality
            play(url: stream.url)
        }
    }
    
    func togglePlayback() {
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
    }
    
    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    func seekRelative(_ seconds: Double) {
        let target = max(0, min(duration, currentTime + seconds))
        seek(to: target)
    }
    
    func changeQuality(_ stream: VideoStream) {
        currentQuality = stream.quality
        let wasPlaying = isPlaying
        let currentPos = currentTime
        play(url: stream.url)
        if currentPos > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.seek(to: currentPos)
                if wasPlaying { self.player?.play() }
            }
        }
    }
    
    func toggleMute() {
        volume = volume > 0 ? 0 : 1.0
        player?.volume = volume
    }
    
    private func removeTimeObserver() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
    
    deinit {
        // @MainActor properties can't be accessed in deinit.
        // Time observer will be cleaned up when the player is deallocated.
    }
}