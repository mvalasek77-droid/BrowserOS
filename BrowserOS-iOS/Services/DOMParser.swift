import Foundation

// MARK: - DOM Parser
// Parses JavaScript extraction results from WKWebView into native Swift model types

struct DOMParser {
    
    // MARK: - JavaScript Injection Strings
    
    /// JavaScript to inject into WKWebView to extract the page DOM structure as JSON
    static var domExtractionJavaScript: String {
        return """
        (function() {
            var result = [];
            var baseTag = document.querySelector('base');
            var baseURL = baseTag ? baseTag.href : window.location.href;
            
            function resolveURL(path) {
                if (!path) return '';
                if (path.startsWith('http://') || path.startsWith('https://')) return path;
                if (path.startsWith('//')) return 'https:' + path;
                if (path.startsWith('/')) {
                    try {
                        var u = new URL(baseURL);
                        return u.protocol + '//' + u.host + path;
                    } catch(e) { return path; }
                }
                return baseURL + '/' + path;
            }
            
            function getText(el) {
                return (el.innerText || el.textContent || '').trim();
            }
            
            // Headings h1-h6
            var headings = document.querySelectorAll('h1, h2, h3, h4, h5, h6');
            headings.forEach(function(h) {
                var level = parseInt(h.tagName.charAt(1));
                var text = getText(h);
                if (text) result.push({type: 'heading', text: text, level: level});
            });
            
            // Paragraphs
            var paras = document.querySelectorAll('p');
            paras.forEach(function(p) {
                var text = getText(p);
                if (text && text.length > 10) {
                    result.push({type: 'paragraph', text: text});
                }
            });
            
            // Links
            var links = document.querySelectorAll('a[href]');
            links.forEach(function(a) {
                var text = getText(a);
                var href = a.getAttribute('href');
                if (text && href && !href.startsWith('#') && !href.startsWith('javascript:')) {
                    result.push({type: 'link', text: text, url: resolveURL(href)});
                }
            });
            
            // Images
            var imgs = document.querySelectorAll('img[src]');
            imgs.forEach(function(img) {
                var src = img.getAttribute('src');
                var alt = img.getAttribute('alt') || '';
                if (src && src.length > 5) {
                    result.push({type: 'image', url: resolveURL(src), alt: alt});
                }
            });
            
            // List items
            var lists = document.querySelectorAll('ul, ol');
            lists.forEach(function(list) {
                var ordered = list.tagName === 'OL';
                var items = list.querySelectorAll('li');
                items.forEach(function(li) {
                    var text = getText(li);
                    if (text) {
                        result.push({type: 'listItem', text: text, ordered: ordered});
                    }
                });
            });
            
            // Blockquotes
            var quotes = document.querySelectorAll('blockquote');
            quotes.forEach(function(bq) {
                var text = getText(bq);
                if (text) result.push({type: 'blockquote', text: text});
            });
            
            // Code blocks
            var pres = document.querySelectorAll('pre');
            pres.forEach(function(pre) {
                var text = getText(pre);
                if (text) result.push({type: 'codeBlock', text: text});
            });
            
            // Horizontal rules
            var hrs = document.querySelectorAll('hr');
            hrs.forEach(function() {
                result.push({type: 'divider'});
            });
            
            // Tables
            var tables = document.querySelectorAll('table');
            tables.forEach(function(table) {
                var headers = [];
                var rows = [];
                var ths = table.querySelectorAll('th');
                ths.forEach(function(th) {
                    headers.push(getText(th));
                });
                var trs = table.querySelectorAll('tr');
                trs.forEach(function(tr) {
                    var cells = [];
                    var tds = tr.querySelectorAll('td');
                    if (tds.length > 0) {
                        tds.forEach(function(td) {
                            cells.push(getText(td));
                        });
                        rows.push(cells);
                    }
                });
                if (headers.length > 0 || rows.length > 0) {
                    result.push({type: 'table', headers: headers, rows: rows});
                }
            });
            
            // Forms
            var forms = document.querySelectorAll('form');
            forms.forEach(function(form, formIdx) {
                var inputs = [];
                var fields = form.querySelectorAll('input, select, textarea');
                fields.forEach(function(field) {
                    var type = (field.getAttribute('type') || field.tagName.toLowerCase()).toLowerCase();
                    // Skip non-user-visible fields, but they'll still be submitted by the form
                    if (type === 'hidden' || type === 'submit' || type === 'button' || type === 'image' || type === 'reset') {
                        if (type === 'submit') {
                            inputs.push({
                                name: field.getAttribute('name') || '',
                                type: type,
                                placeholder: field.getAttribute('value') || null,
                                value: null,
                                label: null
                            });
                        }
                        return;
                    }
                    inputs.push({
                        name: field.getAttribute('name') || '',
                        type: type,
                        placeholder: field.getAttribute('placeholder') || null,
                        value: field.value || null,
                        label: findLabel(field)
                    });
                });
                if (inputs.length > 0) {
                    result.push({
                        type: 'form',
                        formIndex: formIdx,
                        action: resolveURL(form.getAttribute('action') || baseURL),
                        method: (form.getAttribute('method') || 'GET').toUpperCase(),
                        inputs: inputs
                    });
                }
            });
            
            function findLabel(field) {
                var id = field.getAttribute('id');
                if (id) {
                    var label = document.querySelector('label[for="' + id + '"]');
                    if (label) return getText(label);
                }
                var parentLabel = field.closest('label');
                if (parentLabel) return getText(parentLabel);
                return null;
            }
            
            return JSON.stringify(result);
        })();
        """
    }
    
    /// JavaScript to extract reader-mode article content
    static var readerModeJavaScript: String {
        return """
        (function() {
            function getText(el) {
                return (el.innerText || el.textContent || '').trim();
            }
            
            var result = {
                title: '',
                byline: null,
                content: [],
                url: window.location.href
            };
            
            // Extract title
            var ogTitle = document.querySelector('meta[property="og:title"]');
            var titleTag = document.querySelector('title');
            var h1Tag = document.querySelector('h1');
            result.title = (ogTitle ? ogTitle.getAttribute('content') : '') ||
                           (h1Tag ? getText(h1Tag) : '') ||
                           (titleTag ? getText(titleTag) : '') ||
                           'Untitled';
            
            // Extract byline / author
            var authorMeta = document.querySelector('meta[name="author"]') ||
                             document.querySelector('meta[property="article:author"]');
            if (authorMeta) {
                result.byline = authorMeta.getAttribute('content');
            }
            var timeTag = document.querySelector('time');
            if (timeTag && !result.byline) {
                result.byline = getText(timeTag);
            }
            
            // Find article content
            var articleEl = document.querySelector('article') ||
                           document.querySelector('[role="main"]') ||
                           document.querySelector('main');
            
            if (!articleEl) {
                articleEl = document.body;
            }
            
            // Walk through article children and extract content blocks
            var walker = document.createTreeWalker(articleEl, NodeFilter.SHOW_ELEMENT, null);
            var node;
            while (node = walker.nextNode()) {
                var tag = node.tagName.toLowerCase();
                
                if (/^h[1-6]$/.test(tag)) {
                    var level = parseInt(tag.charAt(1));
                    var text = getText(node);
                    if (text) {
                        result.content.push({type: 'heading', text: text, level: level});
                    }
                } else if (tag === 'p') {
                    var text = getText(node);
                    if (text && text.length > 15) {
                        result.content.push({type: 'text', text: text});
                    }
                } else if (tag === 'blockquote') {
                    var text = getText(node);
                    if (text) result.content.push({type: 'quote', text: text});
                } else if (tag === 'pre' || (tag === 'code' && node.parentElement && node.parentElement.tagName.toLowerCase() === 'pre')) {
                    var text = getText(node);
                    if (text) result.content.push({type: 'code', text: text});
                }
            }
            
            return JSON.stringify(result);
        })();
        """
    }
    
    /// JavaScript to submit a form: locates form by DOM index, fills the
    /// provided fields, fires input+change events (so onChange validators run),
    /// and clicks the submit button (preferring click over form.submit() so the
    /// page's onSubmit handlers and onClick validation fire).
    static func formSubmitJavaScript(formIndex: Int, values: [String: String]) -> String {
        guard let valuesData = try? JSONSerialization.data(withJSONObject: values, options: []),
              let valuesJSON = String(data: valuesData, encoding: .utf8) else {
            return "false"
        }
        return """
        (function() {
            var form = document.forms[\(formIndex)];
            if (!form) { return 'form_not_found'; }
            var values = \(valuesJSON);
            for (var name in values) {
                if (!values.hasOwnProperty(name)) continue;
                var field = form.elements[name];
                if (!field) continue;
                try {
                    field.focus();
                    field.value = values[name];
                    field.dispatchEvent(new Event('input', { bubbles: true }));
                    field.dispatchEvent(new Event('change', { bubbles: true }));
                    field.blur();
                } catch(e) { /* ignore per-field errors */ }
            }
            var btn = form.querySelector('input[type="submit"], button[type="submit"], button:not([type])');
            try {
                if (btn) { btn.click(); }
                else { form.submit(); }
            } catch(e) { form.submit(); }
            return 'submitted';
        })();
        """
    }

    /// JavaScript to detect media elements in the page
    static var mediaDetectionJavaScript: String {
        return """
        (function() {
            var items = [];
            
            // YouTube embeds
            var ytFrames = document.querySelectorAll('iframe[src*="youtube.com/embed"], iframe[src*="youtube.com/v/"], iframe[src*="youtu.be"]');
            ytFrames.forEach(function(iframe) {
                var src = iframe.getAttribute('src') || '';
                var match = src.match(/(?:embed|v)\\/([a-zA-Z0-9_-]{11})/);
                if (match) {
                    items.push({
                        type: 'youtube',
                        videoId: match[1],
                        src: src,
                        title: iframe.getAttribute('title') || 'YouTube Video'
                    });
                }
            });
            
            // Vimeo embeds
            var vimeoFrames = document.querySelectorAll('iframe[src*="player.vimeo.com"], iframe[src*="vimeo.com/video"]');
            vimeoFrames.forEach(function(iframe) {
                var src = iframe.getAttribute('src') || '';
                var match = src.match(/vimeo\\.com\\/video\\/([0-9]+)/);
                if (match) {
                    items.push({
                        type: 'vimeo',
                        videoId: match[1],
                        src: src,
                        title: iframe.getAttribute('title') || 'Vimeo Video'
                    });
                }
            });
            
            // HTML5 video elements
            var videos = document.querySelectorAll('video');
            videos.forEach(function(video) {
                var src = video.getAttribute('src');
                var poster = video.getAttribute('poster') || null;
                if (!src) {
                    var source = video.querySelector('source[src]');
                    if (source) src = source.getAttribute('src');
                }
                if (src) {
                    items.push({
                        type: 'direct',
                        src: src,
                        poster: poster,
                        title: 'Video'
                    });
                }
            });
            
            // Source elements with video type
            var sources = document.querySelectorAll('source[type^="video/"]');
            sources.forEach(function(source) {
                var src = source.getAttribute('src');
                if (src) {
                    items.push({
                        type: 'direct',
                        src: src,
                        poster: null,
                        title: 'Video Stream'
                    });
                }
            });
            
            // Open Graph video meta tags
            var ogVideo = document.querySelector('meta[property="og:video"]') ||
                         document.querySelector('meta[property="og:video:url"]') ||
                         document.querySelector('meta[property="og:video:secure_url"]');
            var ogTitle = document.querySelector('meta[property="og:title"]');
            var ogImage = document.querySelector('meta[property="og:image"]');
            
            if (ogVideo) {
                items.push({
                    type: 'ogVideo',
                    src: ogVideo.getAttribute('content') || '',
                    title: ogTitle ? ogTitle.getAttribute('content') : 'Video',
                    thumbnail: ogImage ? ogImage.getAttribute('content') : null
                });
            }
            
            return JSON.stringify(items);
        })();
        """
    }
    
    // MARK: - Parsing Methods
    
    /// Parse the JSON result of DOM extraction into [NativeWebElement]
    static func parseElements(from json: String) -> [NativeWebElement] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        
        var elements: [NativeWebElement] = []
        
        for item in array {
            guard let type = item["type"] as? String else { continue }
            
            switch type {
            case "heading":
                if let text = item["text"] as? String,
                   let level = item["level"] as? Int {
                    elements.append(.heading(text, level))
                }
                
            case "paragraph":
                if let text = item["text"] as? String {
                    elements.append(.paragraph(text))
                }
                
            case "link":
                if let text = item["text"] as? String,
                   let url = item["url"] as? String {
                    elements.append(.link(text: text, url: url))
                }
                
            case "image":
                if let url = item["url"] as? String {
                    let alt = item["alt"] as? String ?? ""
                    elements.append(.image(url: url, alt: alt))
                }
                
            case "listItem":
                if let text = item["text"] as? String {
                    let ordered = item["ordered"] as? Bool ?? false
                    elements.append(.listItem(text, ordered))
                }
                
            case "blockquote":
                if let text = item["text"] as? String {
                    elements.append(.blockquote(text))
                }
                
            case "codeBlock":
                if let text = item["text"] as? String {
                    elements.append(.codeBlock(text))
                }
                
            case "divider":
                elements.append(.divider)
                
            case "table":
                if let headers = item["headers"] as? [String],
                   let rows = item["rows"] as? [[String]] {
                    elements.append(.table(headers: headers, rows: rows))
                }
                
            case "form":
                if let inputsData = item["inputs"] as? [[String: Any]] {
                    var formFields: [FormField] = []
                    for input in inputsData {
                        let field = FormField(
                            name: input["name"] as? String ?? "",
                            type: input["type"] as? String ?? "text",
                            placeholder: input["placeholder"] as? String,
                            value: input["value"] as? String,
                            label: input["label"] as? String
                        )
                        formFields.append(field)
                    }
                    if !formFields.isEmpty {
                        let formIndex = item["formIndex"] as? Int ?? 0
                        let action = item["action"] as? String ?? ""
                        let method = item["method"] as? String ?? "GET"
                        elements.append(.form(formIndex: formIndex, action: action, method: method, inputs: formFields))
                    }
                }
                
            default:
                break
            }
        }
        
        return elements
    }
    
    /// Parse the JSON result of reader mode extraction into ReaderContent
    static func parseReaderContent(from json: String, url: String) -> ReaderContent? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        guard let title = dict["title"] as? String, !title.isEmpty else { return nil }
        let byline = dict["byline"] as? String
        
        var blocks: [ReaderContent.ReaderBlock] = []
        
        if let contentArray = dict["content"] as? [[String: Any]] {
            for item in contentArray {
                guard let type = item["type"] as? String else { continue }
                
                switch type {
                case "text":
                    if let text = item["text"] as? String, !text.isEmpty {
                        blocks.append(.text(text))
                    }
                case "heading":
                    if let text = item["text"] as? String,
                       let level = item["level"] as? Int {
                        blocks.append(.heading(text, level))
                    }
                case "code":
                    if let text = item["text"] as? String, !text.isEmpty {
                        blocks.append(.code(text))
                    }
                case "quote":
                    if let text = item["text"] as? String, !text.isEmpty {
                        blocks.append(.quote(text))
                    }
                default:
                    break
                }
            }
        }
        
        guard !blocks.isEmpty else { return nil }
        
        return ReaderContent(
            title: title,
            byline: byline,
            content: blocks,
            url: url
        )
    }
    
    /// Parse the JSON result of media detection into [MediaItem]
    static func parseMediaItems(from json: String, url: String) -> [MediaItem] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        
        var items: [MediaItem] = []
        var seenURLs: Set<String> = []
        
        for item in array {
            guard let type = item["type"] as? String else { continue }
            
            var streamURL: String? = item["src"] as? String
            var title: String = item["title"] as? String ?? "Video"
            var thumbnailURL: String? = item["thumbnail"] as? String ?? item["poster"] as? String
            var source: MediaSource = .other
            
            switch type {
            case "youtube":
                source = .youtube
                if let videoId = item["videoId"] as? String {
                    streamURL = "https://www.youtube.com/watch?v=\(videoId)"
                    if thumbnailURL == nil {
                        thumbnailURL = "https://img.youtube.com/vi/\(videoId)/mqdefault.jpg"
                    }
                }
                
            case "vimeo":
                source = .vimeo
                if let videoId = item["videoId"] as? String {
                    streamURL = "https://player.vimeo.com/video/\(videoId)"
                    if thumbnailURL == nil {
                        thumbnailURL = "https://vumbnail.com/\(videoId).jpg"
                    }
                }
                
            case "direct":
                source = .direct
                
            case "ogVideo":
                source = .other
                
            default:
                break
            }
            
            // Deduplicate by stream URL
            if let streamURL = streamURL, !seenURLs.contains(streamURL) {
                seenURLs.insert(streamURL)
                items.append(MediaItem(
                    title: title,
                    thumbnailURL: thumbnailURL,
                    streamURL: streamURL,
                    duration: nil,
                    source: source,
                    pageURL: url
                ))
            }
        }
        
        return items
    }
}