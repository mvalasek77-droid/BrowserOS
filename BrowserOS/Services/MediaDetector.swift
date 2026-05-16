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
    // Uses noembed oEmbed API to get video info, then Invidious/yt-dlp proxies for streams
    
    func extractYouTubeStreams(videoID: String) async -> [VideoStream] {
        var streams: [VideoStream] = []
        
        // Try Invidious instances for direct stream URLs
        let instances = [
            "https://inv.nadeko.net",
            "https://invidious.nerdvpn.de",
            "https://vid.puffyan.us"
        ]
        
        for instance in instances {
            if let streams2 = try? await fetchInvidiousStreams(instance: instance, videoID: videoID) {
                streams.append(contentsOf: streams2)
                if !streams.isEmpty { break }
            }
        }
        
        return streams
    }
    
    private func fetchInvidiousStreams(instance: String, videoID: String) async throws -> [VideoStream] {
        let urlString = "\(instance)/api/v1/videos/\(videoID)"
        guard let url = URL(string: urlString) else { return [] }
        
        let request = URLRequest(url: url, timeoutInterval: 10)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else { return [] }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        
        var streams: [VideoStream] = []
        
        // Parse formatStreams (adaptive) and formatStreams (progressive)
        if let formatStreams = json["formatStreams"] as? [[String: Any]] {
            for format in formatStreams {
                guard let urlStr = format["url"] as? String,
                      let url = URL(string: urlStr) else { continue }
                let quality = format["qualityLabel"] as? String ?? format["quality"] as? String ?? "?"
                let itag = format["itag"] as? String ?? ""
                let type = format["type"] as? String ?? "video/mp4"
                let formatStr = type.contains("webm") ? "webm" : "mp4"
                
                streams.append(VideoStream(
                    quality: quality,
                    url: url,
                    format: formatStr,
                    bitrate: Int(format["bitrate"] as? String ?? "0")
                ))
            }
        }
        
        // Also check adaptiveFormats for HLS
        if let adaptiveFormats = json["adaptiveFormats"] as? [[String: Any]] {
            for format in adaptiveFormats {
                guard let urlStr = format["url"] as? String,
                      let url = URL(string: urlStr),
                      let type = format["type"] as? String,
                      type.hasPrefix("video/") else { continue }
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