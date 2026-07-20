import Foundation

// MARK: - DOM Parser
// Parses JavaScript extraction results from WKWebView into native Swift model types.
// Includes site-specific extractors for popular SPAs (YouTube, Facebook, X/Twitter,
// Instagram, Reddit, Tinder, ChatGPT, Claude, xAI) that need special handling
// because their content is rendered dynamically via JavaScript.

struct DOMParser {
    
    // MARK: - JavaScript Injection Strings
    
    /// JavaScript to inject into WKWebView to extract the page DOM structure as JSON.
    /// Detects the current site and runs site-specific extraction first, then falls
    /// back to a generic extractor that works on any site.
    static var domExtractionJavaScript: String {
        return """
        (function() {
            var result = [];
            var baseTag = document.querySelector('base');
            var baseURL = baseTag ? baseTag.href : window.location.href;
            var hostname = window.location.hostname || '';
            
            function resolveURL(path) {
                if (!path) return '';
                // new URL() handles absolute URLs (http, data:, etc.),
                // protocol-relative //, root-relative /, and document-relative
                // paths correctly — the old string concatenation produced
                // broken URLs like "https://site/page.html/other.html".
                try { return new URL(path, baseURL).href; } catch(e) { return path; }
            }
            
            function getText(el) {
                return (el.innerText || el.textContent || '').trim();
            }
            
            function addElement(el) {
                if (result.length >= 200) return; // Cap at 200 elements for Watch
                result.push(el);
            }
            
            // ========== SITE-SPECIFIC EXTRACTORS ==========
            // These run first and return early if they produce content.
            // This handles SPAs that render content via JS and have
            // non-semantic DOM structures.
            
            // --- YouTube ---
            if (hostname.includes('youtube.com') || hostname.includes('youtu.be')) {
                // Video title
                var ytTitle = document.querySelector('h1.yt-core-attributed-headline, h1.ytd-watch-metadata h1, h1.style-scope, #info-contents h1, h1.title');
                if (ytTitle) {
                    var t = getText(ytTitle);
                    if (t) addElement({type: 'heading', text: t, level: 1});
                }
                // Channel name
                var ytChannel = document.querySelector('ytd-channel-name a, #channel-name a, .ytd-video-owner-renderer a');
                if (ytChannel) {
                    var ch = getText(ytChannel);
                    if (ch) addElement({type: 'paragraph', text: '📺 ' + ch});
                }
                // Description (expand it first)
                var ytDesc = document.querySelector('#description-inner, #description-inline-expander, ytd-text-inline-renderer, #description .content');
                if (ytDesc) {
                    // Click "Show more" to expand
                    var expandBtn = ytDesc.querySelector('#expand, button[aria-label*="more"]');
                    if (expandBtn) expandBtn.click();
                    var descText = getText(ytDesc);
                    if (descText && descText.length > 5) addElement({type: 'paragraph', text: descText.substring(0, 2000)});
                }
                // Comments
                var ytComments = document.querySelectorAll('ytd-comment-thread-renderer, ytd-comment-renderer');
                var commentCount = 0;
                ytComments.forEach(function(c) {
                    if (commentCount >= 20) return;
                    var author = c.querySelector('#author-text, a.yt-simple-endpoint');
                    var content = c.querySelector('#content-text, .yt-core-attributed-string');
                    if (content) {
                        var a = author ? getText(author) : '';
                        var ct = getText(content);
                        if (ct) {
                            addElement({type: 'paragraph', text: (a ? a + ': ' : '') + ct.substring(0, 500)});
                            commentCount++;
                        }
                    }
                });
                // Related videos
                var ytRelated = document.querySelectorAll('ytd-compact-video-renderer a#video-title, ytd-video-renderer a#video-title');
                var relCount = 0;
                ytRelated.forEach(function(a) {
                    if (relCount >= 15) return;
                    var title = getText(a);
                    var href = a.getAttribute('href');
                    if (title && href) {
                        addElement({type: 'link', text: '▶ ' + title, url: resolveURL(href)});
                        relCount++;
                    }
                });
                // Search results page
                var ytSearchResults = document.querySelectorAll('ytd-video-renderer a#video-title');
                if (ytSearchResults.length > 0) {
                    ytSearchResults.forEach(function(a) {
                        var title = getText(a);
                        var href = a.getAttribute('href');
                        if (title && href) addElement({type: 'link', text: '▶ ' + title, url: resolveURL(href)});
                    });
                }
                if (result.length > 0) return JSON.stringify(result);
            }
            
            // --- Facebook ---
            if (hostname.includes('facebook.com') || hostname.includes('fb.com')) {
                // Facebook posts
                var fbPosts = document.querySelectorAll('[data-ad-preview], [role="article"], div.x1lliihq.x1n2onr6');
                if (fbPosts.length === 0) {
                    fbPosts = document.querySelectorAll('[data-pagelet="FeedUnit_0"], [data-pagelet^="FeedUnit"]');
                }
                // Try the structured feed items
                if (fbPosts.length === 0) {
                    fbPosts = document.querySelectorAll('div[data-testid="post_message"]');
                }
                fbPosts.forEach(function(post, idx) {
                    if (idx >= 25) return;
                    // Author
                    var author = post.querySelector('a[role="link"] strong, h4 a, span.x1lliihq a');
                    if (author) {
                        var a = getText(author);
                        if (a) addElement({type: 'heading', text: a, level: 2});
                    }
                    // Post text
                    var msg = post.querySelector('[data-testid="post_message"], div[data-ad-preview], .x1lliihq.x1n2onr6');
                    if (!msg) msg = post.querySelector('[dir="auto"]');
                    if (msg) {
                        var mt = getText(msg);
                        if (mt && mt.length > 3) addElement({type: 'paragraph', text: mt.substring(0, 1500)});
                    }
                    // Links in the post
                    var links = post.querySelectorAll('a[href]');
                    links.forEach(function(link) {
                        var lt = getText(link);
                        var lh = link.getAttribute('href');
                        if (lt && lh && !lh.startsWith('#') && lt.length > 3) {
                            addElement({type: 'link', text: lt.substring(0, 200), url: resolveURL(lh)});
                        }
                    });
                    // Images
                    var imgs = post.querySelectorAll('img[src]');
                    imgs.forEach(function(img) {
                        var src = img.getAttribute('src');
                        var alt = img.getAttribute('alt') || '';
                        if (src && !src.includes('emoji') && !src.includes('rsrc.php')) {
                            addElement({type: 'image', url: resolveURL(src), alt: alt.substring(0, 100)});
                        }
                    });
                });
                if (result.length > 0) return JSON.stringify(result);
            }
            
            // --- X/Twitter ---
            if (hostname.includes('twitter.com') || hostname.includes('x.com')) {
                var tweets = document.querySelectorAll('article[data-testid="tweet"]');
                if (tweets.length === 0) {
                    tweets = document.querySelectorAll('[data-testid="tweetText"]');
                }
                tweets.forEach(function(tweet, idx) {
                    if (idx >= 30) return;
                    // Author
                    var authorEl = tweet.querySelector('[data-testid="User-Name"] a, a[role="link"] time');
                    if (authorEl) {
                        var authorLink = authorEl.closest('a');
                        var authorName = authorLink ? getText(authorLink) : '';
                        if (authorName) addElement({type: 'heading', text: authorName, level: 3});
                    }
                    // Tweet text
                    var tweetText = tweet.querySelector('[data-testid="tweetText"], [lang]');
                    if (tweetText) {
                        var tt = getText(tweetText);
                        if (tt) addElement({type: 'paragraph', text: tt.substring(0, 1000)});
                    }
                    // Links
                    var links = tweet.querySelectorAll('a[href]');
                    links.forEach(function(link) {
                        var lt = getText(link);
                        var lh = link.getAttribute('href');
                        if (lt && lh && !lh.includes('/status/') && lt.length > 5) {
                            addElement({type: 'link', text: lt.substring(0, 200), url: resolveURL(lh)});
                        }
                    });
                });
                if (result.length > 0) return JSON.stringify(result);
            }
            
            // --- Instagram ---
            if (hostname.includes('instagram.com')) {
                var igPosts = document.querySelectorAll('article, div[role="button"] a[href*="/p/"], a[href*="/reel/"]');
                igPosts.forEach(function(post, idx) {
                    if (idx >= 20) return;
                    var img = post.querySelector('img[srcset]');
                    if (img) {
                        var src = img.getAttribute('srcset')?.split(',')[0]?.split(' ')[0] || img.getAttribute('src');
                        var alt = img.getAttribute('alt') || '';
                        if (src) addElement({type: 'image', url: resolveURL(src), alt: alt.substring(0, 200)});
                    }
                    var caption = post.querySelector('h1, span[role="presentation"], div[role="button"] span');
                    if (caption) {
                        var ct = getText(caption);
                        if (ct && ct.length > 3) addElement({type: 'paragraph', text: ct.substring(0, 500)});
                    }
                });
                // Fallback: just grab all images
                if (result.length === 0) {
                    var igImages = document.querySelectorAll('img[srcset], img[src]');
                    igImages.forEach(function(img, idx) {
                        if (idx >= 20) return;
                        var src = img.getAttribute('srcset')?.split(',')[0]?.split(' ')[0] || img.getAttribute('src') || '';
                        var alt = img.getAttribute('alt') || '';
                        if (src && !src.includes('cdn_instagram') && src.length > 10) {
                            addElement({type: 'image', url: resolveURL(src), alt: alt.substring(0, 100)});
                        }
                    });
                }
                if (result.length > 0) return JSON.stringify(result);
            }
            
            // --- Reddit ---
            if (hostname.includes('reddit.com') || hostname.includes('redd.it')) {
                // Old Reddit
                var redditEntries = document.querySelectorAll('.thing.link, .thing.comment');
                if (redditEntries.length > 0) {
                    redditEntries.forEach(function(entry, idx) {
                        if (idx >= 25) return;
                        var titleEl = entry.querySelector('a.title, p.title a');
                        if (titleEl) {
                            addElement({type: 'link', text: getText(titleEl), url: resolveURL(titleEl.getAttribute('href'))});
                        }
                        var bodyEl = entry.querySelector('.usertext-body .md, .usertext-body p');
                        if (bodyEl) {
                            var bt = getText(bodyEl);
                            if (bt && bt.length > 5) addElement({type: 'paragraph', text: bt.substring(0, 1000)});
                        }
                    });
                    if (result.length > 0) return JSON.stringify(result);
                }
                // New Reddit (SPA)
                var shRedditPosts = document.querySelectorAll('shreddit-post, article[data-testid]');
                shRedditPosts.forEach(function(post, idx) {
                    if (idx >= 25) return;
                    var titleEl = post.querySelector('a[slot="title"], h2, h3, [data-testid="post-title"]');
                    if (titleEl) {
                        var title = getText(titleEl);
                        if (title) addElement({type: 'heading', text: title, level: 2});
                    }
                    var bodyEl = post.querySelector('[data-testid="post-comment-text"], .text-neutral-content, div[slot="text-body"]');
                    if (bodyEl) {
                        var bt = getText(bodyEl);
                        if (bt && bt.length > 5) addElement({type: 'paragraph', text: bt.substring(0, 1000)});
                    }
                });
                if (result.length === 0) {
                    // Last resort: grab all links with scores
                    document.querySelectorAll('[data-testid="post-container"]').forEach(function(post, idx) {
                        if (idx >= 25) return;
                        var title = post.querySelector('h2, h3, a[data-testid="post-title"]');
                        if (title) {
                            var t = getText(title);
                            var h = title.getAttribute('href') || title.closest('a')?.getAttribute('href') || '';
                            if (t) addElement({type: 'link', text: t, url: resolveURL(h)});
                        }
                    });
                }
                if (result.length > 0) return JSON.stringify(result);
            }
            
            // --- Tinder (desktop web) ---
            if (hostname.includes('tinder.com')) {
                // Profile cards
                var profiles = document.querySelectorAll('[data-testid="profileCard"], div[class*="profile"]');
                profiles.forEach(function(profile, idx) {
                    if (idx >= 10) return;
                    var nameEl = profile.querySelector('[data-testid="profileName"], h1, h2');
                    if (nameEl) addElement({type: 'heading', text: getText(nameEl), level: 2});
                    var bioEl = profile.querySelector('[data-testid="profileBio"], div[class*="bio"]');
                    if (bioEl) {
                        var bio = getText(bioEl);
                        if (bio) addElement({type: 'paragraph', text: bio.substring(0, 500)});
                    }
                    var imgs = profile.querySelectorAll('img[src]');
                    imgs.forEach(function(img) {
                        var src = img.getAttribute('src');
                        if (src && src.includes('images-')) {
                            addElement({type: 'image', url: resolveURL(src), alt: ''});
                        }
                    });
                });
                if (result.length > 0) return JSON.stringify(result);
            }
            
            // --- ChatGPT ---
            if (hostname.includes('chatgpt.com') || hostname.includes('chat.openai.com')) {
                var messages = document.querySelectorAll('[data-testid="conversation-turn-2"], [data-message-author-role], .text-base');
                if (messages.length === 0) {
                    messages = document.querySelectorAll('.prose, [class*="markdown"]');
                }
                messages.forEach(function(msg, idx) {
                    if (idx >= 50) return;
                    var role = msg.getAttribute('data-message-author-role') || '';
                    var text = getText(msg);
                    if (text && text.length > 3) {
                        var prefix = role === 'user' ? '👤 ' : '🤖 ';
                        addElement({type: 'paragraph', text: prefix + text.substring(0, 2000)});
                    }
                    // Code blocks
                    msg.querySelectorAll('pre code, code').forEach(function(code) {
                        var ct = getText(code);
                        if (ct && ct.length > 10) addElement({type: 'codeBlock', text: ct.substring(0, 3000)});
                    });
                });
                if (result.length > 0) return JSON.stringify(result);
            }
            
            // --- Claude.ai ---
            if (hostname.includes('claude.ai')) {
                var claudeMsgs = document.querySelectorAll('[data-testid="human-message"], [data-testid="assistant-message"], .prose');
                if (claudeMsgs.length === 0) {
                    claudeMsgs = document.querySelectorAll('[class*="message"], .font-user-message, [class*="human"]');
                }
                claudeMsgs.forEach(function(msg, idx) {
                    if (idx >= 50) return;
                    var isHuman = msg.getAttribute('data-testid')?.includes('human') || msg.className.includes('human') || msg.className.includes('user');
                    var text = getText(msg);
                    if (text && text.length > 3) {
                        var prefix = isHuman ? '👤 ' : '🤖 ';
                        addElement({type: 'paragraph', text: prefix + text.substring(0, 2000)});
                    }
                });
                if (result.length > 0) return JSON.stringify(result);
            }
            
            // --- xAI / Grok ---
            if (hostname.includes('grok.com') || hostname.includes('x.ai')) {
                var grokMsgs = document.querySelectorAll('[class*="message"], [class*="response"], [class*="turn"]');
                grokMsgs.forEach(function(msg, idx) {
                    if (idx >= 50) return;
                    var text = getText(msg);
                    if (text && text.length > 3) {
                        addElement({type: 'paragraph', text: text.substring(0, 2000)});
                    }
                    msg.querySelectorAll('pre code').forEach(function(code) {
                        var ct = getText(code);
                        if (ct && ct.length > 10) addElement({type: 'codeBlock', text: ct.substring(0, 3000)});
                    });
                });
                if (result.length > 0) return JSON.stringify(result);
            }
            
            // ========== GENERIC EXTRACTOR ==========
            // Fallback for all other sites. Walk matching elements in DOCUMENT
            // ORDER so the page reads top-to-bottom — the old per-type passes
            // emitted all headings, then all paragraphs, then all links,
            // scrambling the page beyond readability. Navigation chrome and
            // hidden elements are skipped.
            var seenTexts = {};
            function isJunk(el) {
                if (el.closest('nav, footer, aside, [role="navigation"], [role="banner"], [aria-hidden="true"], script, style, noscript')) return true;
                // Null offsetParent = hidden (display:none subtree).
                if (el.offsetParent === null) return true;
                // Anything inside a position:fixed overlay (cookie banners,
                // chat bubbles, floating bars) is junk on a watch. Children of
                // fixed containers have a non-null offsetParent, so walk up.
                try {
                    var n = el;
                    while (n && n.nodeType === 1 && n !== document.body) {
                        if (getComputedStyle(n).position === 'fixed') return true;
                        n = n.parentElement;
                    }
                } catch (e) {}
                return false;
            }

            var nodes = document.querySelectorAll('h1, h2, h3, h4, h5, h6, p, li, blockquote, pre, img[src], a[href], hr, table');
            nodes.forEach(function(el) {
                if (result.length >= 200) return;
                if (isJunk(el)) return;
                var tag = el.tagName.toLowerCase();

                if (/^h[1-6]$/.test(tag)) {
                    var text = getText(el);
                    if (text && !seenTexts['h:' + text]) {
                        seenTexts['h:' + text] = 1;
                        addElement({type: 'heading', text: text, level: parseInt(tag.charAt(1))});
                    }
                } else if (tag === 'p') {
                    if (el.closest('blockquote, li')) return; // parent captures the text
                    var text = getText(el);
                    if (text && text.length > 10 && !seenTexts['p:' + text]) {
                        seenTexts['p:' + text] = 1;
                        addElement({type: 'paragraph', text: text});
                    }
                } else if (tag === 'li') {
                    // Nested list items are already captured in the outer li's text.
                    if (el.parentElement && el.parentElement.closest('li')) return;
                    var text = getText(el);
                    if (text && !seenTexts['li:' + text]) {
                        seenTexts['li:' + text] = 1;
                        addElement({type: 'listItem', text: text, ordered: !!el.closest('ol')});
                    }
                } else if (tag === 'a') {
                    // Links whose text already appears inside a captured block
                    // (paragraph, heading, list item…) would duplicate it.
                    if (el.closest('p, li, h1, h2, h3, h4, h5, h6, blockquote, td, th, figcaption')) return;
                    var text = getText(el);
                    var href = el.getAttribute('href');
                    if (!text || text.length < 3 || !href || href.startsWith('#') || href.startsWith('javascript:')) return;
                    if (seenTexts['a:' + text]) return;
                    seenTexts['a:' + text] = 1;
                    addElement({type: 'link', text: text, url: resolveURL(href)});
                } else if (tag === 'img') {
                    var src = el.getAttribute('src');
                    var alt = el.getAttribute('alt') || '';
                    var w = el.naturalWidth || el.width;
                    var h = el.naturalHeight || el.height;
                    // Only content-sized images — icons/spacers/trackers are noise.
                    if (src && src.length > 5 && w > 80 && h > 60) {
                        addElement({type: 'image', url: resolveURL(src), alt: alt.substring(0, 200)});
                    }
                } else if (tag === 'blockquote') {
                    var text = getText(el);
                    if (text) addElement({type: 'blockquote', text: text});
                } else if (tag === 'pre') {
                    var text = getText(el);
                    if (text) addElement({type: 'codeBlock', text: text});
                } else if (tag === 'hr') {
                    addElement({type: 'divider'});
                } else if (tag === 'table') {
                    var headers = [];
                    var rows = [];
                    el.querySelectorAll('th').forEach(function(th) { headers.push(getText(th)); });
                    el.querySelectorAll('tr').forEach(function(tr) {
                        var cells = [];
                        var tds = tr.querySelectorAll('td');
                        if (tds.length > 0) {
                            tds.forEach(function(td) { cells.push(getText(td)); });
                            rows.push(cells);
                        }
                    });
                    if (headers.length > 0 || rows.length > 0) {
                        addElement({type: 'table', headers: headers, rows: rows});
                    }
                }
            });
            
            // Forms
            var forms = document.querySelectorAll('form');
            // Track which input elements are already captured inside a <form>
            // so the orphan-password fallback below doesn't duplicate them.
            var capturedInputs = new Set();
            forms.forEach(function(form, formIdx) {
                var inputs = [];
                var fields = form.querySelectorAll('input, select, textarea');
                fields.forEach(function(field) {
                    capturedInputs.add(field);
                    var type = (field.getAttribute('type') || field.tagName.toLowerCase()).toLowerCase();
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
                    addElement({
                        type: 'form',
                        formIndex: formIdx,
                        action: resolveURL(form.getAttribute('action') || baseURL),
                        method: (form.getAttribute('method') || 'GET').toUpperCase(),
                        inputs: inputs
                    });
                }
            });

            // Orphan password/email inputs (SPA login screens like Claude,
            // Facebook, Google that render inputs outside a <form> element).
            // Synthesize a virtual form so the watch's LoginDetector can flag it.
            var orphanPwd = document.querySelector('input[type="password"]');
            if (orphanPwd && !capturedInputs.has(orphanPwd)) {
                var orphanInputs = [];
                document.querySelectorAll('input[type="password"], input[type="email"], input[type="text"]').forEach(function(field) {
                    if (capturedInputs.has(field)) return;
                    var type = (field.getAttribute('type') || 'text').toLowerCase();
                    orphanInputs.push({
                        name: field.getAttribute('name') || '',
                        type: type,
                        placeholder: field.getAttribute('placeholder') || null,
                        value: null,
                        label: findLabel(field)
                    });
                });
                if (orphanInputs.length > 0) {
                    addElement({
                        type: 'form',
                        formIndex: forms.length,
                        action: baseURL,
                        method: 'POST',
                        inputs: orphanInputs
                    });
                }
            }
            
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
            
            // If generic extractor found nothing, try a last-resort text dump
            if (result.length === 0) {
                var body = document.body || document.documentElement;
                var allText = getText(body);
                if (allText.length > 50) {
                    // Split into chunks of ~500 chars at sentence boundaries
                    var sentences = allText.match(/[^.!?]+[.!?]+/g) || [allText.substring(0, 5000)];
                    sentences.slice(0, 20).forEach(function(s) {
                        var trimmed = s.trim();
                        if (trimmed.length > 10) addElement({type: 'paragraph', text: trimmed});
                    });
                }
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
                } else if (tag === 'pre') {
                    // Only <pre> — the walker also visits its <code> child, and
                    // matching both emitted every code block twice.
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
    ///
    /// For SPAs (Facebook, ChatGPT, Claude, Google) the orphan-password
    /// detector synthesizes a virtual form whose index is `document.forms.length`.
    /// That index does not exist in `document.forms`, so we fall back to filling
    /// the first visible password/email/text inputs and clicking the nearest
    /// submit button — or pressing Enter on the password field.
    static func formSubmitJavaScript(formIndex: Int, values: [String: String]) -> String {
        guard let valuesData = try? JSONSerialization.data(withJSONObject: values, options: []),
              let valuesJSON = String(data: valuesData, encoding: .utf8) else {
            return "false"
        }
        return """
        (function() {
            var values = \(valuesJSON);
            var form = document.forms[\(formIndex)];

            function fillField(field, value) {
                if (!field || value == null) return false;
                try {
                    field.focus();
                    // React and other controlled inputs cache the native setter, so use it.
                    var nativeInputSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set;
                    var nativeTextareaSetter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value')?.set;
                    if (nativeInputSetter && field instanceof window.HTMLInputElement) {
                        nativeInputSetter.call(field, value);
                    } else if (nativeTextareaSetter && field instanceof window.HTMLTextAreaElement) {
                        nativeTextareaSetter.call(field, value);
                    } else {
                        field.value = value;
                    }
                    ['focus', 'input', 'change', 'keyup', 'keydown', 'keypress', 'blur'].forEach(function(evt) {
                        field.dispatchEvent(new Event(evt, { bubbles: true, cancelable: true }));
                    });
                    return true;
                } catch(e) { return false; }
            }

            function clickSubmit(startNode) {
                // Prefer an explicit submit button inside or near the form.
                var candidates = [];
                if (startNode) {
                    candidates = Array.from(startNode.querySelectorAll('input[type="submit"], button[type="submit"], button:not([type])'));
                }
                if (candidates.length === 0) {
                    candidates = Array.from(document.querySelectorAll('input[type="submit"], button[type="submit"], button:not([type])'));
                }
                // Click the first visible button whose text/aria-label suggests submission.
                for (var i = 0; i < candidates.length; i++) {
                    var btn = candidates[i];
                    var text = (btn.innerText || btn.value || btn.getAttribute('aria-label') || '').toLowerCase();
                    if (text.match(/(submit|log in|login|sign in|signin|continue|next|go|start)/)) {
                        try { btn.click(); return true; } catch(e) {}
                    }
                }
                // Fallback: click the first visible candidate.
                for (var i = 0; i < candidates.length; i++) {
                    var btn = candidates[i];
                    var rect = btn.getBoundingClientRect();
                    if (rect.width > 0 && rect.height > 0) {
                        try { btn.click(); return true; } catch(e) {}
                    }
                }
                return false;
            }

            if (form) {
                // Real HTML form path.
                for (var name in values) {
                    if (!values.hasOwnProperty(name)) continue;
                    var field = form.elements[name];
                    if (!field) continue;
                    fillField(field, values[name]);
                }
                if (clickSubmit(form)) return 'submitted';
                try { form.submit(); } catch(e) {}
                return 'submitted';
            }

            // SPA/orphan form fallback.
            var pwd = document.querySelector('input[type="password"]');
            if (!pwd) return 'form_not_found';
            var container = pwd.closest('form') || pwd.closest('div, section, article, main, body');
            var fields = container ? Array.from(container.querySelectorAll('input[type="password"], input[type="email"], input[type="text"], input[type="tel"], input:not([type])')) : [];
            if (fields.length === 0) {
                fields = Array.from(document.querySelectorAll('input[type="password"], input[type="email"], input[type="text"], input[type="tel"], input:not([type])'));
            }

            // Fill by name match first.
            for (var name in values) {
                if (!values.hasOwnProperty(name)) continue;
                var matched = fields.find(function(f) { return (f.name || f.id || f.placeholder || '').toLowerCase() === name.toLowerCase(); });
                if (!matched) {
                    // Type-based heuristic when names don't match.
                    if (name.toLowerCase().includes('pass')) matched = fields.find(function(f) { return f.type === 'password'; });
                    else if (name.toLowerCase().includes('mail') || name.toLowerCase().includes('user') || name.toLowerCase().includes('login')) {
                        matched = fields.find(function(f) { return f.type === 'email' || f.type === 'text'; });
                    }
                }
                fillField(matched, values[name]);
            }

            if (clickSubmit(container || pwd)) return 'submitted';

            // Last resort: dispatch Enter key on the password field.
            try {
                pwd.focus();
                var event = new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true });
                pwd.dispatchEvent(event);
                var up = new KeyboardEvent('keyup', { key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true });
                pwd.dispatchEvent(up);
            } catch(e) {}
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
            
            // YouTube watch page — extract video ID from URL
            if (window.location.hostname.includes('youtube.com') || window.location.hostname.includes('youtu.be')) {
                var vidMatch = window.location.href.match(/[?&]v=([a-zA-Z0-9_-]{11})/);
                if (!vidMatch) vidMatch = window.location.pathname.match(/\\/([a-zA-Z0-9_-]{11})(?:\\?|$)/);
                if (vidMatch) {
                    var ytTitle = document.querySelector('h1.yt-core-attributed-headline, h1.title, h1');
                    items.push({
                        type: 'youtube',
                        videoId: vidMatch[1],
                        src: window.location.href,
                        title: ytTitle ? (ytTitle.innerText || 'YouTube Video').trim() : 'YouTube Video'
                    });
                }
            }
            
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
            
            // HTML5 video elements. Track seen srcs — a <video> with a
            // <source> child would otherwise be captured by both passes.
            var seenDirect = {};
            var videos = document.querySelectorAll('video');
            videos.forEach(function(video) {
                var src = video.getAttribute('src');
                var poster = video.getAttribute('poster') || null;
                if (!src) {
                    var source = video.querySelector('source[src]');
                    if (source) src = source.getAttribute('src');
                }
                if (src && !seenDirect[src]) {
                    seenDirect[src] = 1;
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
                if (src && !seenDirect[src]) {
                    seenDirect[src] = 1;
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
            let title: String = item["title"] as? String ?? "Video"
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