import Foundation

// MARK: - HTML Native Renderer
// Revolutionary: Parses HTML and converts to native SwiftUI elements
// No WKWebView needed — pure native rendering on watchOS

actor HTMLNativeRenderer {
    
    func render(html: String, baseURL: String) -> [NativeWebElement] {
        var elements: [NativeWebElement] = []
        let cleaned = preprocessHTML(html)
        let tokens = tokenize(cleaned)
        
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            
            switch token {
            case .openTag(let tag, let attrs):
                switch tag.lowercased() {
                case "h1"..."h6":
                    if let level = Int(tag.replacingOccurrences(of: "h", with: "")) {
                        var text = ""
                        var j = i + 1
                        while j < tokens.count {
                            if case .closeTag(let ct) = tokens[j], ct.lowercased() == tag.lowercased() { break }
                            if case .text(let t) = tokens[j] { text += t }
                            j += 1
                        }
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            elements.append(.heading(text.trimmingCharacters(in: .whitespacesAndNewlines), level))
                        }
                        i = j
                    }
                    
                case "p":
                    var text = ""
                    var j = i + 1
                    while j < tokens.count {
                        if case .closeTag(let ct) = tokens[j], ct.lowercased() == "p" { break }
                        switch tokens[j] {
                        case .text(let t): text += t
                        case .openTag("a", let aAttrs):
                            let href = aAttrs["href"] ?? ""
                            let linkText = collectText(from: tokens, start: j)
                            if !linkText.isEmpty {
                                let resolved = resolveURL(href, base: baseURL)
                                elements.append(.link(text: linkText, url: resolved))
                            }
                        case .openTag("strong", _), .openTag("b", _), .openTag("em", _), .openTag("i", _):
                            text += collectText(from: tokens, start: j)
                        default: break
                        }
                        j += 1
                    }
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        elements.append(.paragraph(trimmed))
                    }
                    i = j
                    
                case "a":
                    let href = attrs["href"] ?? ""
                    let linkText = collectTextFromTokens(tokens, from: i)
                    if !linkText.isEmpty {
                        let resolved = resolveURL(href, base: baseURL)
                        elements.append(.link(text: linkText, url: resolved))
                    }
                    
                case "img":
                    let src = attrs["src"] ?? ""
                    let alt = attrs["alt"] ?? ""
                    if !src.isEmpty {
                        let resolved = resolveURL(src, base: baseURL)
                        elements.append(.image(url: resolved, alt: alt))
                    }
                    
                case "ul", "ol":
                    let ordered = tag.lowercased() == "ol"
                    var j = i + 1
                    while j < tokens.count {
                        if case .closeTag(let ct) = tokens[j], ct.lowercased() == tag.lowercased() { break }
                        if case .openTag("li", _) = tokens[j] {
                            let liText = collectText(from: tokens, start: j)
                            if !liText.isEmpty {
                                elements.append(.listItem(liText, ordered))
                            }
                        }
                        j += 1
                    }
                    i = j
                    
                case "blockquote":
                    let text = collectText(from: tokens, start: i)
                    if !text.isEmpty {
                        elements.append(.blockquote(text))
                    }
                    
                case "pre", "code":
                    let text = collectText(from: tokens, start: i)
                    if !text.isEmpty {
                        elements.append(.codeBlock(text))
                    }
                    
                case "hr":
                    elements.append(.divider)
                    
                case "table":
                    let (headers, rows) = parseTable(tokens: tokens, from: i)
                    if !headers.isEmpty || !rows.isEmpty {
                        elements.append(.table(headers: headers, rows: rows))
                    }
                    
                default: break
                }
                
            case .text(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && elements.count > 0 {
                    // Append orphan text as paragraph only if substantial
                    if trimmed.count > 10 {
                        elements.append(.paragraph(trimmed))
                    }
                }
                
            default: break
            }
            i += 1
        }
        
        return elements.isEmpty ? [.paragraph("No content to display")] : elements
    }
    
    // MARK: - Reader Mode Extraction
    // Mozilla Readability-inspired algorithm for watchOS
    
    func extractReaderContent(html: String, url: String) -> ReaderContent? {
        let title = extractTitle(from: html) ?? "Untitled"
        let byline = extractByline(from: html)
        let bodyHTML = extractArticleBody(from: html)
        
        guard !bodyHTML.isEmpty else { return nil }
        
        var blocks: [ReaderContent.ReaderBlock] = []
        let tokens = tokenize(preprocessHTML(bodyHTML))
        
        var i = 0
        while i < tokens.count {
            let token = tokens[i]
            
            switch token {
            case .openTag(let tag, _):
                switch tag.lowercased() {
                case "h1"..."h6":
                    if let level = Int(tag.replacingOccurrences(of: "h", with: "")) {
                        let text = collectText(from: tokens, start: i)
                        if !text.isEmpty {
                            blocks.append(.heading(text, level))
                        }
                    }
                case "p":
                    let text = collectText(from: tokens, start: i)
                    if !text.isEmpty {
                        blocks.append(.text(text))
                    }
                case "ul", "ol":
                    let ordered = tag.lowercased() == "ol"
                    var items: [String] = []
                    var j = i + 1
                    while j < tokens.count {
                        if case .closeTag(let ct) = tokens[j], ct.lowercased() == tag.lowercased() { break }
                        if case .openTag("li", _) = tokens[j] {
                            items.append(collectText(from: tokens, start: j))
                        }
                        j += 1
                    }
                    if !items.isEmpty {
                        // Store list items as individual text blocks since ReaderBlock simplified
                        for item in items {
                            let prefix = ordered ? "" : "• "
                            blocks.append(.text(prefix + item))
                        }
                    }
                    i = j
                case "blockquote":
                    let text = collectText(from: tokens, start: i)
                    if !text.isEmpty { blocks.append(.quote(text)) }
                case "pre", "code":
                    let text = collectText(from: tokens, start: i)
                    if !text.isEmpty { blocks.append(.code(text)) }
                case "img":
                    // Skip images in reader mode if compress_images setting on
                    break
                default: break
                }
            default: break
            }
            i += 1
        }
        
        guard !blocks.isEmpty else { return nil }
        
        return ReaderContent(
            title: title,
            byline: byline,
            content: blocks,
            url: url
        )
    }
    
    // MARK: - Private Helpers
    
    private func preprocessHTML(_ html: String) -> String {
        var result = html
        // Remove script and style tags with content
        result = result.replacingOccurrences(
            of: "<script[^>]*>[\\s\\S]*?</script>",
            with: "",
            options: .regularExpression,
            range: nil
        )
        result = result.replacingOccurrences(
            of: "<style[^>]*>[\\s\\S]*?</style>",
            with: "",
            options: .regularExpression,
            range: nil
        )
        result = result.replacingOccurrences(
            of: "<nav[^>]*>[\\s\\S]*?</nav>",
            with: "",
            options: .regularExpression,
            range: nil
        )
        result = result.replacingOccurrences(
            of: "<footer[^>]*>[\\s\\S]*?</footer>",
            with: "",
            options: .regularExpression,
            range: nil
        )
        result = result.replacingOccurrences(
            of: "<header[^>]*>[\\s\\S]*?</header>",
            with: "",
            options: .regularExpression,
            range: nil
        )
        // Remove comments
        result = result.replacingOccurrences(
            of: "<!--[\\s\\S]*?-->",
            with: "",
            options: .regularExpression,
            range: nil
        )
        return result
    }
    
    // MARK: - Tokenizer
    
    private enum HTMLToken {
        case openTag(String, [String: String])
        case closeTag(String)
        case text(String)
    }
    
    private func tokenize(_ html: String) -> [HTMLToken] {
        var tokens: [HTMLToken] = []
        var current = html
        let tagPattern = #"</?([a-zA-Z][a-zA-Z0-9]*)([^>]*)>"#
        
        while !current.isEmpty {
            if let range = current.range(of: tagPattern, options: .regularExpression) {
                let before = String(current[current.startIndex..<range.lowerBound])
                if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    tokens.append(.text(decodeEntities(before)))
                }
                
                let tagStr = String(current[range])
                let isClosing = tagStr.hasPrefix("</")
                let tagNameRange = tagStr.range(of: #"[a-zA-Z][a-zA-Z0-9]*"#, options: .regularExpression, range: tagStr.startIndex..<tagStr.endIndex)!
                let tagName = String(tagStr[tagNameRange]).lowercased()
                
                if isClosing {
                    tokens.append(.closeTag(tagName))
                } else {
                    let afterName = tagStr.index(after: tagNameRange.upperBound)
                    let beforeClose = tagStr.index(before: range.upperBound)
                    let attrsStr = afterName < beforeClose ? String(tagStr[afterName..<beforeClose]) : ""
                    let attrs = parseAttributes(attrsStr)
                    tokens.append(.openTag(tagName, attrs))
                }
                
                current = String(current[range.upperBound...])
            } else {
                if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    tokens.append(.text(decodeEntities(current)))
                }
                break
            }
        }
        
        return tokens
    }
    
    private func parseAttributes(_ str: String) -> [String: String] {
        var attrs: [String: String] = [:]
        let pattern = #"([a-zA-Z][a-zA-Z0-9-]*)\s*=\s*"([^"]*)""#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(str.startIndex..., in: str)
            regex.enumerateMatches(in: str, range: range) { match, _, _ in
                guard let match = match else { return }
                if let nameRange = Range(match.range(at: 1), in: str),
                   let valueRange = Range(match.range(at: 2), in: str) {
                    attrs[String(str[nameRange])] = String(str[valueRange])
                }
            }
        }
        return attrs
    }
    
    private func collectText(from tokens: [HTMLToken], start: Int) -> String {
        var text = ""
        var depth = 0
        var j = start
        while j < tokens.count {
            switch tokens[j] {
            case .openTag: depth += 1
            case .closeTag:
                if depth > 0 { depth -= 1 }
                else { break }
            case .text(let t): text += t + " "
            }
            j += 1
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func collectTextFromTokens(_ tokens: [HTMLToken], from start: Int) -> String {
        var text = ""
        var j = start + 1
        while j < tokens.count {
            if case .closeTag = tokens[j] { break }
            if case .text(let t) = tokens[j] { text += t }
            j += 1
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func resolveURL(_ path: String, base: String) -> String {
        if path.hasPrefix("http://") || path.hasPrefix("https://") { return path }
        if path.hasPrefix("//") { return "https:" + path }
        if path.hasPrefix("/") {
            guard let baseURL = URL(string: base), let scheme = baseURL.scheme, let host = baseURL.host else {
                return path
            }
            return "\(scheme)://\(host)\(path)"
        }
        return base + "/" + path
    }
    
    private func decodeEntities(_ str: String) -> String {
        var result = str
        let entities: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'",
            "&nbsp;": " ", "&mdash;": "—", "&ndash;": "–",
            "&hellip;": "…", "&copy;": "©", "&reg;": "®",
            "&trade;": "™"
        ]
        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        // Numeric entities
        result = result.replacingOccurrences(
            of: "&#([0-9]+);",
            with: "",
            options: .regularExpression
        )
        return result
    }
    
    // MARK: - Article Extraction (Readability Lite)
    
    private func extractTitle(from html: String) -> String? {
        let patterns = [
            #"<h1[^>]*>(.*?)</h1>"#,
            #"<title[^>]*>(.*?)</title>"#,
            #"<meta[^>]*property="og:title"[^>]*content="([^"]*)""#,
            #"<meta[^>]*name="title"[^>]*content="([^"]*)""#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let title = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { return decodeEntities(title) }
            }
        }
        return nil
    }
    
    private func extractByline(from html: String) -> String? {
        let patterns = [
            #"<meta[^>]*name="author"[^>]*content="([^"]*)""#,
            #"<meta[^>]*property="article:author"[^>]*content="([^"]*)""#,
            #"""author"[^>]*>(.*?)</span>"#,
            #"<time[^>]*>(.*?)</time>"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let byline = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !byline.isEmpty { return decodeEntities(byline) }
            }
        }
        return nil
    }
    
    private func extractArticleBody(from html: String) -> String {
        // Try article tag first
        if let regex = try? NSRegularExpression(pattern: #"<article[^>]*>([\s\S]*?)</article>"#, options: .dotMatchesLineSeparators),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            let body = String(html[range])
            if body.count > 100 { return body }
        }
        
        // Try main tag
        if let regex = try? NSRegularExpression(pattern: #"<main[^>]*>([\s\S]*?)</main>"#, options: .dotMatchesLineSeparators),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            let body = String(html[range])
            if body.count > 100 { return body }
        }
        
        // Try role=main
        if let regex = try? NSRegularExpression(pattern: #"<[^>]*role="main"[^>]*>([\s\S]*?)</"#, options: .dotMatchesLineSeparators),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            let body = String(html[range])
            if body.count > 100 { return body }
        }
        
        // Fallback: find the largest text block between <p> tags
        if let regex = try? NSRegularExpression(pattern: #"<p[^>]*>([\s\S]*?)</p>"#, options: .dotMatchesLineSeparators) {
            let range = NSRange(html.startIndex..., in: html)
            var bestBlock = ""
            regex.enumerateMatches(in: html, range: range) { match, _, _ in
                guard let match = match,
                      let r = Range(match.range(at: 1), in: html) else { return }
                let block = String(html[r])
                if block.count > bestBlock.count {
                    bestBlock = block
                }
            }
            if bestBlock.count > 50 { return "<p>" + bestBlock + "</p>" }
        }
        
        return html
    }
    
    private func parseTable(tokens: [HTMLToken], from start: Int) -> (headers: [String], rows: [[String]]) {
        var headers: [String] = []
        var rows: [[String]] = []
        var currentRow: [String] = []
        var inHeader = false
        
        var j = start
        var depth = 0
        while j < tokens.count {
            switch tokens[j] {
            case .openTag(let tag, _):
                switch tag.lowercased() {
                case "table": depth += 1
                case "th": inHeader = true
                case "td", "tr": break
                default: break
                }
            case .closeTag(let tag):
                switch tag.lowercased() {
                case "th":
                    inHeader = false
                case "tr":
                    if !currentRow.isEmpty {
                        if headers.isEmpty {
                            headers = currentRow
                        } else {
                            rows.append(currentRow)
                        }
                        currentRow = []
                    }
                case "table":
                    if depth > 0 { depth -= 1 }
                    if depth == 0 {
                        if !currentRow.isEmpty { rows.append(currentRow) }
                        return (headers, rows)
                    }
                default: break
                }
            case .text(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    currentRow.append(trimmed)
                }
            }
            j += 1
        }
        return (headers, rows)
    }
}