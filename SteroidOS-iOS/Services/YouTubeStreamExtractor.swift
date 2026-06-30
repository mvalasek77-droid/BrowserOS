import Foundation

// MARK: - YouTube Stream Extractor (iPhone side)
// Extracts playable direct stream URLs for YouTube videos so the watch can
// play them in AVPlayer. The iPhone has a full network stack and can hit
// public Invidious instances that are often blocked/rate-limited on the
// watch's more restricted network path.
//
// We don't bundle a yt-dlp binary (App Store review risk + binary size), so
// the extraction relies on the Invidious API. Multiple instances are tried
// in order, and results are cached so a replay within the TTL doesn't
// re-hit the network.

actor YouTubeStreamExtractor {
    static let shared = YouTubeStreamExtractor()

    /// In-memory cache keyed by videoID. Invidious stream URLs are signed and
    /// time-limited, so entries expire after `cacheTTL` seconds.
    private var cache: [String: (streams: [VideoStream], fetchedAt: Date)] = [:]
    private let cacheTTL: TimeInterval = 60 * 10  // 10 minutes

    /// Public Invidious instances tried in order. The iPhone can reach more
    /// of these than the watch because it isn't behind the watch's network
    /// sandbox.
    private let instances = [
        "https://inv.nadeko.net",
        "https://invidious.nerdvpn.de",
        "https://vid.puffyan.us",
        "https://invidious.private.coffee",
        "https://invidious.einfachzocken.eu",
        "https://invidious.slusd.eu",
        "https://invidious.f5.si",
        "https://yewtu.be",
        "https://invidious.jing.rocks"
    ]

    /// Extract all available streams for a video, trying multiple Invidious
    /// instances until one succeeds. Returns an empty array if every instance
    /// fails (the caller should then surface an error to the watch).
    func extractStreams(videoID: String) async -> [VideoStream] {
        // Cache hit?
        if let entry = cache[videoID],
           Date().timeIntervalSince(entry.fetchedAt) < cacheTTL,
           !entry.streams.isEmpty {
            return entry.streams
        }

        var streams: [VideoStream] = []

        for instance in instances {
            do {
                let result = try await fetchInvidiousStreams(instance: instance, videoID: videoID)
                if !result.isEmpty {
                    streams = result
                    break
                }
            } catch {
                // Instance down/rate-limited — try the next one.
                continue
            }
        }

        cache[videoID] = (streams, Date())
        return streams
    }

    private func fetchInvidiousStreams(instance: String, videoID: String) async throws -> [VideoStream] {
        let urlString = "\(instance)/api/v1/videos/\(videoID)?fields=formatStreams,adaptiveFormats"
        guard let url = URL(string: urlString) else { return [] }

        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("SteroidOS/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return [] }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        var streams: [VideoStream] = []
        var seen: Set<String> = []

        // Progressive (muxed audio+video) streams — preferred for the watch.
        if let formatStreams = json["formatStreams"] as? [[String: Any]] {
            for format in formatStreams {
                guard let urlStr = format["url"] as? String,
                      let url = URL(string: urlStr),
                      !seen.contains(urlStr) else { continue }
                seen.insert(urlStr)
                let quality = format["qualityLabel"] as? String ?? format["quality"] as? String ?? "?"
                let type = format["type"] as? String ?? "video/mp4"
                let formatStr = type.contains("webm") ? "webm" : "mp4"
                let bitrate: Int? = {
                    if let i = format["bitrate"] as? Int { return i }
                    if let s = format["bitrate"] as? String, let i = Int(s) { return i }
                    return nil
                }()
                streams.append(VideoStream(quality: quality, url: url, format: formatStr, bitrate: bitrate))
            }
        }

        // Adaptive (video-only) fallback — only if no muxed streams exist,
        // because the watch will lose audio on a video-only track.
        if streams.isEmpty, let adaptiveFormats = json["adaptiveFormats"] as? [[String: Any]] {
            for format in adaptiveFormats {
                guard let urlStr = format["url"] as? String,
                      let url = URL(string: urlStr),
                      let type = format["type"] as? String,
                      type.hasPrefix("video/"),
                      !seen.contains(urlStr) else { continue }
                seen.insert(urlStr)
                let quality = format["qualityLabel"] as? String ?? format["quality"] as? String ?? "?"
                let formatStr = type.contains("webm") ? "webm" : "mp4"
                streams.append(VideoStream(quality: quality, url: url, format: formatStr, bitrate: nil))
            }
        }

        return streams
    }

    // MARK: - Stream Selection

    /// Pick the best stream for watch playback, preferring low resolutions
    /// for smooth performance on the small watch screen. Nonisolated so the
    /// phone manager can call it without awaiting the actor.
    nonisolated static func pickBestStream(from streams: [VideoStream], preferredQuality: String) -> VideoStream? {
        // Exact preferred-quality match.
        if preferredQuality != "auto",
           let exact = streams.first(where: { $0.quality == preferredQuality }) {
            return exact
        }
        // Watch-friendly ladder: 240p → 360p → 144p → 270p.
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
}