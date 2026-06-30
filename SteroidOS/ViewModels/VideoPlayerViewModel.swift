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
    
    // Nonisolated reference for safe cleanup in deinit
    private var playerForCleanup: AVPlayer?

    func play(url: URL) {
        removeTimeObserver()
        player?.pause()
        cancellables.removeAll()
        
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        playerForCleanup = newPlayer
        
        // Observe item status
        item.publisher(for: \.status)
            .sink { [weak self] status in
                switch status {
                case .unknown:
                    break
                case .readyToPlay:
                    self?.isBuffering = false
                    let seconds = item.duration.seconds
                    self?.duration = seconds.isFinite ? seconds : 0
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
            MainActor.assumeIsolated {
                self?.currentTime = time.seconds
            }
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
        await playYouTube(videoID: videoID, preferredQuality: "360p")
    }
    
    func playYouTube(videoID: String, preferredQuality: String) async {
        // Show a clear loading state immediately so the user sees something
        // is happening while streams are being resolved.
        isBuffering = true
        errorMessage = nil
        availableQualities = []
        currentQuality = preferredQuality
        
        // Preferred path: ask the iPhone to extract a direct stream URL.
        // The iPhone has a full network stack and can run yt-dlp-style
        // extraction that the watch cannot. This is the most reliable route.
        if let relayed = await requestStreamFromiPhone(videoID: videoID, quality: preferredQuality) {
            // The iPhone may return either a single resolved URL or a list
            // of streams. Prefer the single URL; otherwise pick from the list.
            if let urlStr = relayed.streamURL, let url = URL(string: urlStr) {
                availableQualities = relayed.streams
                currentQuality = relayed.chosenQuality ?? preferredQuality
                play(url: url)
                return
            } else if !relayed.streams.isEmpty {
                availableQualities = relayed.streams
                if let chosen = pickBestStream(from: relayed.streams, preferredQuality: preferredQuality) {
                    currentQuality = chosen.quality
                    play(url: chosen.url)
                    return
                }
            }
            // iPhone relay responded but with nothing usable — fall through to
            // the on-watch Invidious path as a backup.
        }
        
        // Fallback path: on-watch Invidious extraction. Opt-in via Settings,
        // because public Invidious instances are frequently rate-limited or
        // down. Even when "disabled" we still try it as a last resort for
        // on-watch playback, since the alternative is no playback at all.
        let invidiousEnabled = UserDefaults.standard.bool(forKey: "steroidos_invidious_enabled")
        
        let detector = MediaDetector()
        let streams = await detector.extractYouTubeStreams(videoID: videoID)
        
        if streams.isEmpty {
            if invidiousEnabled {
                errorMessage = "Could not extract video stream. The iPhone relay and all Invidious instances failed. Try again, or open in the YouTube app on your iPhone."
            } else {
                errorMessage = "Could not extract a playable stream. Make sure your iPhone is reachable (it performs the extraction), or enable YouTube Stream Extraction in Settings."
            }
            isBuffering = false
            return
        }
        
        availableQualities = streams
        
        // For watch performance, prefer 240p then 360p, then whatever is
        // closest below 360p, then any available stream.
        guard let bestStream = pickBestStream(from: streams, preferredQuality: preferredQuality) else {
            errorMessage = "No compatible video stream found for this video."
            isBuffering = false
            return
        }
        
        currentQuality = bestStream.quality
        play(url: bestStream.url)
    }
    
    // MARK: - iPhone Stream Relay (WatchConnectivity)
    
    /// Result of an iPhone stream-extraction relay request.
    private struct RelayResult {
        var streamURL: String?
        var streams: [VideoStream]
        var chosenQuality: String?
    }
    
    /// Ask the iPhone to extract a playable direct stream URL for a YouTube
    /// video. Uses WatchConnectivity interactive messaging (which supports a
    /// reply). Returns nil if the iPhone is unreachable or doesn't respond in
    /// time, so the caller can fall back to on-watch Invidious extraction.
    private func requestStreamFromiPhone(videoID: String, quality: String) async -> RelayResult? {
        guard WatchSessionManager.shared.isPhoneReachable else { return nil }
        
        let message: [String: Any] = [
            WCKey.messageType.rawValue: WCMessageType.playMedia.rawValue,
            WCKey.videoId.rawValue: videoID,
            WCKey.quality.rawValue: quality,
            WCKey.timestamp.rawValue: Date().timeIntervalSince1970
        ]
        
        return await withCheckedContinuation { continuation in
            WatchSessionManager.shared.requestMediaPlayback(message: message) { reply in
                guard let reply = reply else {
                    // No response / error — the relay failed.
                    continuation.resume(returning: nil)
                    return
                }
                
                var result = RelayResult(streamURL: nil, streams: [], chosenQuality: nil)
                result.streamURL = reply[WCKey.streamUrl.rawValue] as? String
                result.chosenQuality = reply[WCKey.quality.rawValue] as? String
                
                if let streamsJSON = reply[WCKey.streams.rawValue] as? String,
                   let data = streamsJSON.data(using: .utf8) {
                    result.streams = (try? JSONDecoder().decode([VideoStream].self, from: data)) ?? []
                }
                
                continuation.resume(returning: result)
            }
        }
    }
    
    /// Pick the best stream for watch playback, preferring low resolutions
    /// for smooth performance on the small watch screen. `preferredQuality`
    /// is honoured first, then we fall back to the cheapest acceptable stream.
    private func pickBestStream(from streams: [VideoStream], preferredQuality: String) -> VideoStream? {
        // Exact preferred-quality match.
        if preferredQuality != "auto",
           let exact = streams.first(where: { $0.quality == preferredQuality }) {
            return exact
        }
        // Watch-friendly ladder: 240p → 360p → anything ≤ 360p → first available.
        let ladder = ["240p", "360p", "144p", "270p"]
        for q in ladder {
            if let s = streams.first(where: { $0.quality.contains(q) }) {
                return s
            }
        }
        // Anything with a numeric height ≤ 360.
        if let low = streams.first(where: {
            let digits = $0.quality.filter("0123456789".contains)
            if let h = Int(digits) { return h <= 360 }
            return false
        }) {
            return low
        }
        return streams.first
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.seek(to: currentPos)
                if wasPlaying { self?.player?.play() }
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
        // Clean up time observer and pause player using nonisolated reference
        if let observer = timeObserver {
            playerForCleanup?.removeTimeObserver(observer)
        }
        playerForCleanup?.pause()
    }
}