import Foundation

// MARK: - YouTube Web Extractor
// Parses ytInitialPlayerResponse from a YouTube watch page and returns
// playable stream URLs for the Watch. The JSON can come from the iPhone
// WKWebView (preferred) or from a direct page fetch (fallback).

struct YouTubeWebExtractor {

    /// JavaScript that returns window.ytInitialPlayerResponse as a JSON string.
    /// Falls back to reading it from the script tags if the global variable isn't set.
    static let javaScriptToReadPlayerResponse = """
    (function() {
        var response = window.ytInitialPlayerResponse;
        if (response && typeof response === 'object') {
            return JSON.stringify(response);
        }
        var scripts = document.querySelectorAll('script');
        var marker = 'ytInitialPlayerResponse = ';
        for (var i = 0; i < scripts.length; i++) {
            var text = scripts[i].text || '';
            var idx = text.indexOf(marker);
            if (idx !== -1) {
                var start = idx + marker.length;
                var braceCount = 0;
                var inString = false;
                var quote = null;
                var escaped = false;
                for (var j = start; j < text.length; j++) {
                    var c = text[j];
                    if (inString) {
                        if (escaped) {
                            escaped = false;
                        } else if (c === '\\\\') {
                            escaped = true;
                        } else if (c === quote) {
                            inString = false;
                            quote = null;
                        }
                    } else {
                        if (c === '"' || c === "'") {
                            inString = true;
                            quote = c;
                        } else if (c === '{') {
                            braceCount++;
                        } else if (c === '}') {
                            braceCount--;
                            if (braceCount === 0) {
                                try {
                                    return JSON.stringify(JSON.parse(text.substring(start, j + 1)));
                                } catch (e) {
                                    return null;
                                }
                            }
                        }
                    }
                }
            }
        }
        return null;
    })();
    """

    /// Parse a ytInitialPlayerResponse JSON string into [VideoStream].
    static func parsePlayerResponse(jsonString: String, pageURL: String) -> [VideoStream] {
        guard let data = jsonString.data(using: .utf8),
              let playerResponse = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return []
        }
        return parseStreams(from: playerResponse, pageURL: pageURL)
    }

    /// Parse progressive/adaptive formats from the player response.
    private static func parseStreams(from playerResponse: [String: Any], pageURL: String) -> [VideoStream] {
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
    private static func decodeFormatURL(format: [String: Any]) -> String? {
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
            let encodedSignature = signature.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? signature
            let separator = streamURL.contains("?") ? "&" : "?"
            return "\(streamURL)\(separator)\(signatureParam)=\(encodedSignature)"
        }

        return streamURL
    }
}
