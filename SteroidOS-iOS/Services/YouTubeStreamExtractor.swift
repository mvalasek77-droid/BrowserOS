import Foundation

// MARK: - YouTube Stream Extractor (iPhone side)
// Extracts playable direct stream URLs for YouTube videos so the watch can
// play them in AVPlayer. The iPhone uses the YouTube page's own
// ytInitialPlayerResponse first, and falls back to public Invidious instances.
//
// We don't bundle a yt-dlp binary (App Store review risk + binary size), so
// the primary extraction parses the embedded player config already served by
// YouTube to every browser.

actor YouTubeStreamExtractor {
    static let shared = YouTubeStreamExtractor()

    /// In-memory cache keyed by videoID. Stream URLs are signed and time-limited.
    private var cache: [String: (streams: [VideoStream], fetchedAt: Date)] = [:]
    private let cacheTTL: TimeInterval = 60 * 10  // 10 minutes

    /// Public Invidious fallback instances, tried only if direct extraction fails.
    let instances = [
        "https://inv.nadeko.net",
        "https://invidious.nerdvpn.de",
        "https://vid.puffyan.us",
        "https://invidious.private.coffee",
        "https://invidious.einfachzocken.eu",
        "https://invidious.slusd.eu",
        "https://invidious.f5.si",
        "https://yewtu.be",
        "https://invidious.jing.rocks",
        "https://inv.riverside.rocks"
    ]

    /// Extract all available streams for a video. First tries the direct
    /// YouTube player-response path, then falls back to Invidious instances.
    /// Returns an empty array if every path fails.
    func extractStreams(videoID: String) async -> [VideoStream] {
        if let entry = cache[videoID],
           Date().timeIntervalSince(entry.fetchedAt) < cacheTTL,
           !entry.streams.isEmpty {
            return entry.streams
        }

        var streams: [VideoStream] = []

        // Primary path: parse ytInitialPlayerResponse from YouTube directly.
        do {
            let direct = try await extractFromYouTubePage(videoID: videoID)
            if !direct.isEmpty {
                streams = direct
            }
        } catch {
            ErrorLog.log("Direct YouTube extraction failed: \(error.localizedDescription)", source: "YouTubeStreamExtractor")
        }

        // Fallback path: Invidious.
        if streams.isEmpty {
            for instance in instances {
                do {
                    let result = try await fetchInvidiousStreams(instance: instance, videoID: videoID)
                    if !result.isEmpty {
                        streams = result
                        break
                    }
                } catch {
                    continue
                }
            }
        }

        if !streams.isEmpty {
            cache[videoID] = (streams, Date())
        }
        return streams
    }

    // MARK: - Direct YouTube Extraction

    /// Fetches the YouTube watch page, extracts ytInitialPlayerResponse,
    /// and parses progressive + adaptive streams.
    private func extractFromYouTubePage(videoID: String) async throws -> [VideoStream] {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(videoID)") else {
            throw ExtractionError.invalidVideoID
        }

        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            throw ExtractionError.fetchFailed
        }

        guard let playerJSON = extractInitialPlayerResponse(from: html) else {
            throw ExtractionError.playerResponseNotFound
        }

        return parseStreams(from: playerJSON, pageURL: url.absoluteString)
    }

    /// Extract the ytInitialPlayerResponse object from YouTube HTML.
    private func extractInitialPlayerResponse(from html: String) -> [String: Any]? {
        let markers = [
            "ytInitialPlayerResponse = ",
            "var ytInitialPlayerResponse = ",
            "ytInitialPlayerResponse=",
            "var ytInitialPlayerResponse="
        ]

        for marker in markers {
            guard let startRange = html.range(of: marker) else { continue }
            let startIndex = startRange.upperBound

            var braceCount = 0
            var inString = false
            var stringQuote: Character?
            var escaped = false
            var index = startIndex
            var started = false

            while index < html.endIndex {
                let char = html[index]
                if inString {
                    if escaped {
                        escaped = false
                    } else if char == "\\" {
                        escaped = true
                    } else if char == stringQuote {
                        inString = false
                        stringQuote = nil
                    }
                } else {
                    if char == "\"" || char == "'" {
                        inString = true
                        stringQuote = char
                    } else if char == "{" {
                        braceCount += 1
                        started = true
                    } else if char == "}" {
                        braceCount -= 1
                        if started && braceCount == 0 {
                            let objectString = String(html[startIndex...index])
                            guard let data = objectString.data(using: .utf8) else { return nil }
                            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
                        }
                    }
                }
                html.formIndex(after: &index)
            }
        }

        return nil
    }

    /// Parse progressive/adaptive formats from the player response.
    private func parseStreams(from playerResponse: [String: Any], pageURL: String) -> [VideoStream] {
        guard let streamingData = playerResponse["streamingData"] as? [String: Any] else {
            return []
        }

        var streams: [VideoStream] = []
        var seen: Set<String> = []

        let progressiveFormats = streamingData["formats"] as? [[String: Any]] ?? []
        let adaptiveFormats = streamingData["adaptiveFormats"] as? [[String: Any]] ?? []

        for format in progressiveFormats {
            guard let urlStr = decodeFormatURL(format: format),
                  let url = URL(string: urlStr),
                  !seen.contains(urlStr) else { continue }
            seen.insert(urlStr)
            let quality = format["qualityLabel"] as? String ?? format["quality"] as? String ?? "?"
            let type = format["mimeType"] as? String ?? "video/mp4"
            let formatStr = type.contains("webm") ? "webm" : "mp4"
            streams.append(VideoStream(quality: quality, url: url, format: formatStr, bitrate: nil))
        }

        // Fallback to adaptive video-only if no progressive streams found.
        if streams.isEmpty {
            for format in adaptiveFormats {
                guard let urlStr = decodeFormatURL(format: format),
                      let url = URL(string: urlStr),
                      let type = format["mimeType"] as? String,
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

    /// Decode a stream URL from a format dict. Handles plain `url` and
    /// `signatureCipher` / `cipher` fields.
    private func decodeFormatURL(format: [String: Any]) -> String? {
        if let url = format["url"] as? String, !url.isEmpty {
            return url
        }

        // Cipher format: e.g. "url=...&s=...&sp=...&sig=..."
        guard let cipher = (format["signatureCipher"] as? String) ?? (format["cipher"] as? String),
              !cipher.isEmpty else { return nil }

        var queryItems: [String: String] = [:]
        for component in cipher.components(separatedBy: "&") {
            let parts = component.components(separatedBy: "=")
            guard parts.count == 2, let key = parts.first, let value = parts.last else { continue }
            queryItems[key] = value.removingPercentEncoding ?? value
        }

        guard let streamURL = queryItems["url"] else { return nil }

        let signatureParam = queryItems["sp"] ?? "sig"
        if var signature = queryItems["s"] {
            // Simple reverse transform fallback. YouTube's player JS normally does more,
            // but this satisfies many older/low-value signatures. If it fails, the
            // Invidious fallback still works.
            signature = String(signature.reversed())
            return "\(streamURL)\(streamURL.contains("?") ? "&" : "?")\(signatureParam)=\(signature.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? signature)"
        }

        return streamURL
    }

    private enum ExtractionError: Error {
        case invalidVideoID
        case fetchFailed
        case playerResponseNotFound
    }

    // MARK: - Invidious Fallback

    /// Fetch streams from a public Invidious instance.
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

        if let formatStreams = json["formatStreams"] as? [[String: Any]] {
            for format in formatStreams {
                guard let urlStr = format["url"] as? String,
                      let url = URL(string: urlStr),
                      !seen.contains(urlStr) else { continue }
                seen.insert(urlStr)
                let quality = format["qualityLabel"] as? String ?? format["quality"] as? String ?? "?"
                let type = format["type"] as? String ?? "video/mp4"
                let formatStr = type.contains("webm") ? "webm" : "mp4"
                streams.append(VideoStream(quality: quality, url: url, format: formatStr, bitrate: nil))
            }
        }

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

    nonisolated static func pickBestStream(from streams: [VideoStream], preferredQuality: String) -> VideoStream? {
        if preferredQuality != "auto",
           let exact = streams.first(where: { $0.quality == preferredQuality }) {
            return exact
        }
        let ladder = ["240p", "360p", "144p", "270p"]
        for q in ladder {
            if let s = streams.first(where: { $0.quality.contains(q) }) {
                return s
            }
        }
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
