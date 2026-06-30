import Foundation

// MARK: - Media Detector
// Scans HTML for video content and extracts playable streams
// Types (MediaItem, MediaSource, VideoStream) are defined in SharedModels.swift

actor MediaDetector {
    
    /// Detect all media items in an HTML page
    func detectMedia(in html: String, pageURL: String) -> [MediaItem] {
        var items: [MediaItem] = []
        
        // YouTube videos
        items.append(contentsOf: detectYouTube(html: html, pageURL: pageURL))
        
        // Vimeo videos
        items.append(contentsOf: detectVimeo(html: html, pageURL: pageURL))
        
        // HTML5 <video> elements
        items.append(contentsOf: detectHTML5Video(html: html, pageURL: pageURL))
        
        // Direct video links (mp4, m3u8, etc.)
        items.append(contentsOf: detectDirectLinks(html: html, pageURL: pageURL))
        
        // Open Graph video
        items.append(contentsOf: detectOGVideo(html: html, pageURL: pageURL))
        
        return items
    }
    
    // MARK: - YouTube Detection
    
    private func detectYouTube(html: String, pageURL: String) -> [MediaItem] {
        var items: [MediaItem] = []
        let patterns = [
            #"youtube\.com/watch\?v=([a-zA-Z0-9_-]{11})"#,
            #"youtu\.be/([a-zA-Z0-9_-]{11})"#,
            #"youtube\.com/embed/([a-zA-Z0-9_-]{11})"#,
            #"youtube\.com/v/([a-zA-Z0-9_-]{11})"#,
            #"youtube\.com/shorts/([a-zA-Z0-9_-]{11})"#
        ]
        
        var seenIDs: Set<String> = []
        
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            regex.enumerateMatches(in: html, range: range) { match, _, _ in
                guard let match = match,
                      let idRange = Range(match.range(at: 1), in: html) else { return }
                let videoID = String(html[idRange])
                
                guard !seenIDs.contains(videoID) else { return }
                seenIDs.insert(videoID)
                
                items.append(MediaItem(
                    title: "YouTube Video",
                    thumbnailURL: "https://img.youtube.com/vi/\(videoID)/mqdefault.jpg",
                    streamURL: "https://www.youtube.com/watch?v=\(videoID)",
                    duration: nil,
                    source: .youtube,
                    pageURL: pageURL
                ))
            }
        }
        
        return items
    }
    
    // MARK: - Vimeo Detection
    
    private func detectVimeo(html: String, pageURL: String) -> [MediaItem] {
        var items: [MediaItem] = []
        let patterns = [
            #"vimeo\.com/([0-9]+)"#,
            #"player\.vimeo\.com/video/([0-9]+)"#
        ]
        
        var seenIDs: Set<String> = []
        
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            regex.enumerateMatches(in: html, range: range) { match, _, _ in
                guard let match = match,
                      let idRange = Range(match.range(at: 1), in: html) else { return }
                let videoID = String(html[idRange])
                guard !seenIDs.contains(videoID) else { return }
                seenIDs.insert(videoID)
                
                items.append(MediaItem(
                    title: "Vimeo Video",
                    thumbnailURL: "https://vumbnail.com/\(videoID).jpg",
                    streamURL: "https://player.vimeo.com/video/\(videoID)",
                    duration: nil,
                    source: .vimeo,
                    pageURL: pageURL
                ))
            }
        }
        
        return items
    }
    
    // MARK: - HTML5 Video Detection
    
    private func detectHTML5Video(html: String, pageURL: String) -> [MediaItem] {
        var items: [MediaItem] = []
        
        // <video src="..." or <source src="..."
        let srcPatterns = [
            #"<video[^>]*src="([^"]+)""#,
            #"<source[^>]*src="([^"]+)"[^>]*type="video/[^"]*""#,
            #"<source[^>]*type="video/[^"]*"[^>]*src="([^"]+)"#
        ]
        
        for pattern in srcPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            regex.enumerateMatches(in: html, range: range) { match, _, _ in
                guard let match = match,
                      let srcRange = Range(match.range(at: 1), in: html) else { return }
                let src = String(html[srcRange])
                
                guard !src.isEmpty else { return }
                
                items.append(MediaItem(
                    title: extractVideoTitle(html: html) ?? "Video",
                    thumbnailURL: extractPoster(html: html),
                    streamURL: resolveRelativeURL(src, base: pageURL),
                    duration: nil,
                    source: .direct,
                    pageURL: pageURL
                ))
            }
        }
        
        return items
    }
    
    // MARK: - Direct Video Links
    
    private func detectDirectLinks(html: String, pageURL: String) -> [MediaItem] {
        var items: [MediaItem] = []
        let extensions = ["mp4", "m3u8", "mov", "avi", "mkv", "webm", "ts"]
        
        for ext in extensions {
            let pattern = #"https?://[^"'\s]+\.\#(ext)[^"'\s]*"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            regex.enumerateMatches(in: html, range: range) { match, _, _ in
                guard let match = match,
                      let urlRange = Range(match.range(at: 0), in: html) else { return }
                let url = String(html[urlRange])
                
                guard !url.contains(".min.") else { return } // Skip minified JS/CSS false positives
                
                items.append(MediaItem(
                    title: "Video Stream (\(ext.uppercased()))",
                    thumbnailURL: nil,
                    streamURL: url,
                    duration: nil,
                    source: .direct,
                    pageURL: pageURL
                ))
            }
        }
        
        return items
    }
    
    // MARK: - Open Graph Video
    
    private func detectOGVideo(html: String, pageURL: String) -> [MediaItem] {
        var items: [MediaItem] = []
        let patterns = [
            #"<meta[^>]*property="og:video:url"[^>]*content="([^"]*)""#,
            #"<meta[^>]*property="og:video"[^>]*content="([^"]*)""#,
            #"<meta[^>]*property="og:video:secure_url"[^>]*content="([^"]*)""#
        ]
        
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else { continue }
            let range = NSRange(html.startIndex..., in: html)
            if let match = regex.firstMatch(in: html, range: range),
               let urlRange = Range(match.range(at: 1), in: html) {
                let url = String(html[urlRange])
                if !url.isEmpty {
                    items.append(MediaItem(
                        title: extractOGTitle(html: html) ?? "Video",
                        thumbnailURL: extractOGImage(html: html),
                        streamURL: url,
                        duration: nil,
                        source: .other,
                        pageURL: pageURL
                    ))
                }
            }
        }
        
        return items
    }
    
    // MARK: - YouTube Stream URL Extractor
    // Uses noembed oEmbed API to get video info, then Invidious/yt-dlp proxies for streams.
    // Multiple instances are tried in order; successful results are cached so a
    // replay within the cache TTL doesn't re-hit the network.
    
    /// In-memory cache of extracted streams keyed by videoID. Entries expire
    /// after `cacheTTL` seconds so stale Invidious URLs (which are signed and
    /// time-limited) don't get reused indefinitely.
    private static var streamCache: [String: (streams: [VideoStream], fetchedAt: Date)] = [:]
    private static let cacheTTL: TimeInterval = 60 * 10  // 10 minutes
    
    /// Public test seam + convenience: clear the cache (used when the user
    /// explicitly retries a failed extraction).
    static func clearCache() {
        streamCache.removeAll()
    }
    
    func extractYouTubeStreams(videoID: String) async -> [VideoStream] {
        // Cache hit?
        if let entry = Self.streamCache[videoID],
           Date().timeIntervalSince(entry.fetchedAt) < Self.cacheTTL,
           !entry.streams.isEmpty {
            return entry.streams
        }
        
        var streams: [VideoStream] = []
        
        // A broader, currently-reachable list of public Invidious instances.
        // Order matters: the first one that returns usable streams wins.
        let instances = [
            "https://inv.nadeko.net",
            "https://invidious.nerdvpn.de",
            "https://vid.puffyan.us",
            "https://invidious.private.coffee",
            "https://invidious.einfachzocken.eu",
            "https://invidious.slusd.eu",
            "https://invidious.f5.si"
        ]
        
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
        
        // Cache the result (even if empty, to avoid hammering dead instances
        // for a video that genuinely has no extractable streams).
        Self.streamCache[videoID] = (streams, Date())
        
        return streams
    }
    
    private func fetchInvidiousStreams(instance: String, videoID: String) async throws -> [VideoStream] {
        let urlString = "\(instance)/api/v1/videos/\(videoID)?fields=formatStreams,adaptiveFormats"
        guard let url = URL(string: urlString) else { return [] }
        
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("SteroidOS/1.0 (watchOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return [] }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        
        var streams: [VideoStream] = []
        var seen: Set<String> = []
        
        // Progressive (combined audio+video) streams — preferred for the watch
        // because AVPlayer on watchOS handles a single muxed stream more
        // reliably than separate adaptive tracks.
        if let formatStreams = json["formatStreams"] as? [[String: Any]] {
            for format in formatStreams {
                guard let urlStr = format["url"] as? String,
                      let url = URL(string: urlStr),
                      !seen.contains(urlStr) else { continue }
                seen.insert(urlStr)
                let quality = format["qualityLabel"] as? String ?? format["quality"] as? String ?? "?"
                let type = format["type"] as? String ?? "video/mp4"
                let formatStr = type.contains("webm") ? "webm" : "mp4"
                // Invidious returns bitrate as Int (or omits it); tolerate both.
                let bitrate: Int? = {
                    if let i = format["bitrate"] as? Int { return i }
                    if let s = format["bitrate"] as? String, let i = Int(s) { return i }
                    return nil
                }()
                
                streams.append(VideoStream(
                    quality: quality,
                    url: url,
                    format: formatStr,
                    bitrate: bitrate
                ))
            }
        }
        
        // Adaptive formats — video-only tracks. Only use these as a fallback
        // because the watch will have no audio on a video-only track.
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
                
                streams.append(VideoStream(
                    quality: quality,
                    url: url,
                    format: formatStr,
                    bitrate: nil
                ))
            }
        }
        
        return streams
    }
    
    // MARK: - Video Info via oEmbed / Noembed
    
    func fetchVideoInfo(url: String) async -> (title: String?, thumbnail: String?) {
        let noembedURL = "https://noembed.com/embed?url=\(url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url)"
        guard let requestURL = URL(string: noembedURL) else { return (nil, nil) }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: requestURL)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return (nil, nil) }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            return (
                json["title"] as? String,
                json["thumbnail_url"] as? String
            )
        } catch {
            return (nil, nil)
        }
    }
    
    // MARK: - Helpers
    
    private func extractVideoTitle(html: String) -> String? {
        let patterns = [
            #"<meta[^>]*property="og:title"[^>]*content="([^"]*)""#,
            #"<title[^>]*>(.*?)</title>"#,
            #"<meta[^>]*name="title"[^>]*content="([^"]*)""#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let title = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { return title }
            }
        }
        return nil
    }
    
    private func extractOGTitle(html: String) -> String? {
        let pattern = #"<meta[^>]*property="og:title"[^>]*content="([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }
    
    private func extractOGImage(html: String) -> String? {
        let pattern = #"<meta[^>]*property="og:image"[^>]*content="([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }
    
    private func extractPoster(html: String) -> String? {
        let pattern = #"<video[^>]*poster="([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }
    
    private func resolveRelativeURL(_ path: String, base: String) -> String {
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return path }
        if path.hasPrefix("//") { return "https:" + path }
        if path.hasPrefix("/") {
            guard let url = URL(string: base), let scheme = url.scheme, let host = url.host else { return path }
            return "\(scheme)://\(host)\(path)"
        }
        return base + "/" + path
    }
}
