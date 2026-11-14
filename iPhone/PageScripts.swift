import Foundation

/// JavaScript run inside the page on behalf of the watch.
enum PageScripts {

    /// Encodes a Swift value as a JS literal (strings escaped safely).
    static func literal(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: data, encoding: .utf8) else { return "{}" }
        return json
    }

    /// Clicks whatever is at (px, py) — web-view points — like a finger would.
    /// Returns JSON; when the target is a text field it describes it so the
    /// watch can open text entry.
    static func tap(px: Double, py: Double) -> String {
        """
        (function(px, py) {
          var vv = window.visualViewport;
          var x = vv ? (vv.offsetLeft + px / vv.scale) : px;
          var y = vv ? (vv.offsetTop + py / vv.scale) : py;
          var el = document.elementFromPoint(x, y);
          if (!el) { return JSON.stringify({ hit: false }); }
          var target = el.closest('a,button,input,select,textarea,summary,label,video,[role="button"],[role="link"],[onclick]') || el;
          var editable = el.closest('input:not([type=hidden]):not([type=submit]):not([type=button]):not([type=checkbox]):not([type=radio]):not([type=image]), textarea, [contenteditable=""], [contenteditable="true"]');
          var clickTarget = editable || target;
          var before = location.href;
          var opts = { bubbles: true, cancelable: true, clientX: x, clientY: y, view: window, pointerType: 'touch', isPrimary: true };
          ['pointerdown', 'mousedown', 'pointerup', 'mouseup'].forEach(function(type) {
            try {
              clickTarget.dispatchEvent(type.indexOf('pointer') === 0 ? new PointerEvent(type, opts) : new MouseEvent(type, opts));
            } catch (e) {}
          });
          if (typeof clickTarget.focus === 'function') { try { clickTarget.focus(); } catch (e) {} }
          if (!editable) {
            if (target.tagName === 'VIDEO') {
              try { target.paused ? target.play() : target.pause(); } catch (e) {}
            } else if (typeof target.click === 'function') { target.click(); }
            else { try { target.dispatchEvent(new MouseEvent('click', opts)); } catch (e) {} }
          }
          var link = target.closest ? target.closest('a[href]') : null;
          if (!editable && link && link.href && /^https?:/i.test(link.href) && link.target !== '_blank') {
            setTimeout(function() { if (location.href === before) { location.assign(link.href); } }, 600);
          }
          if (editable) {
            window.__sosActive = editable;
            var ce = editable.getAttribute && editable.getAttribute('contenteditable');
            var tag = editable.tagName;
            var type = (tag === 'TEXTAREA') ? 'textarea'
                     : (ce === '' || ce === 'true') ? 'editable'
                     : (editable.type || 'text').toLowerCase();
            var val = (tag === 'INPUT' || tag === 'TEXTAREA') ? (editable.value || '')
                                                              : (editable.innerText || editable.textContent || '');
            var ph = editable.placeholder
                  || (editable.getAttribute && (editable.getAttribute('aria-label') || editable.getAttribute('title')))
                  || '';
            if (!ph && editable.id) {
              var lbl = document.querySelector('label[for="' + editable.id + '"]');
              if (lbl) { ph = lbl.innerText; }
            }
            var inForm = !!(editable.form || (editable.closest && editable.closest('form')));
            var submitLike = inForm || type === 'search' || type === 'url' || type === 'email';
            return JSON.stringify({
              hit: true, input: true, type: type,
              placeholder: String(ph || '').trim().slice(0, 120),
              value: type === 'password' ? '' : String(val || '').slice(0, 1000),
              submitOnReturn: submitLike
            });
          }
          return JSON.stringify({ hit: true, input: false });
        })(\(px), \(py));
        """
    }

    /// Puts `t` into the field the last watch tap focused and, if `s`, presses Enter.
    static func fillInput(text: String, submit: Bool) -> String {
        """
        (function(data) {
          var el = window.__sosActive || document.activeElement;
          if (!el || el === document.body || !el.isConnected) { el = document.activeElement; }
          if (!el || el === document.body) { return 'no-field'; }
          var tag = el.tagName;
          if (tag === 'INPUT' || tag === 'TEXTAREA') {
            // React/Vue track value via the native setter — using it and
            // dispatching 'input' makes them notice.
            var proto = tag === 'INPUT' ? HTMLInputElement.prototype : HTMLTextAreaElement.prototype;
            var setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
            try { el.focus(); } catch (e) {}
            setter.call(el, data.t);
            el.dispatchEvent(new InputEvent('input', { bubbles: true, data: data.t, inputType: 'insertText' }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
          } else if (el.isContentEditable) {
            el.focus();
            el.textContent = data.t;
            el.dispatchEvent(new InputEvent('input', { bubbles: true, data: data.t, inputType: 'insertText' }));
          }
          if (data.s) {
            var form = el.form || (el.closest ? el.closest('form') : null);
            var keyOpts = { bubbles: true, cancelable: true, key: 'Enter', code: 'Enter', keyCode: 13, which: 13 };
            var notCancelled = el.dispatchEvent(new KeyboardEvent('keydown', keyOpts));
            el.dispatchEvent(new KeyboardEvent('keypress', keyOpts));
            el.dispatchEvent(new KeyboardEvent('keyup', keyOpts));
            if (form && notCancelled) {
              var button = form.querySelector('button[type=submit], input[type=submit]');
              if (button && typeof button.click === 'function') { button.click(); }
              else if (typeof form.requestSubmit === 'function') { try { form.requestSubmit(); } catch (e) { try { form.submit(); } catch (e2) {} } }
              else { try { form.submit(); } catch (e) {} }
            }
          }
          return 'ok';
        })(\(literal(["t": text, "s": submit])));
        """
    }

    /// Fills a saved username + password into the page's login form.
    static func fillLogin(username: String, password: String) -> String {
        """
        (function(data) {
          var pw = document.querySelector('input[type=password]');
          var doc = pw ? (pw.form || pw.closest('form') || document) : document;
          var inputs = Array.from(doc.querySelectorAll('input:not([type=hidden]):not([type=submit]):not([type=button]):not([type=checkbox]):not([type=radio])'));
          var userField = inputs.find(function(i) {
            var n = (i.name||'') + ' ' + (i.id||'') + ' ' + (i.autocomplete||'') + ' ' + (i.placeholder||'');
            return i !== pw && (i.type === 'email' || /user|email|login|acct|identifier|name/i.test(n));
          }) || inputs.find(function(i) { return i !== pw; });
          if (!pw && !userField) { return JSON.stringify({ filled: false }); }
          function setVal(el, v) {
            if (!el) return;
            var proto = el.tagName === 'INPUT' ? HTMLInputElement.prototype : HTMLTextAreaElement.prototype;
            var setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
            try { el.focus(); } catch (e) {}
            setter.call(el, v);
            el.dispatchEvent(new InputEvent('input', { bubbles: true, data: v, inputType: 'insertText' }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
          }
          // Two-step sign-ins (Google, Microsoft) show the username first.
          setVal(userField, data.u);
          if (pw) { setVal(pw, data.p); window.__sosActive = pw; } else { window.__sosActive = userField; }
          return JSON.stringify({ filled: true, user: !!userField, pass: !!pw });
        })(\(literal(["u": username, "p": password])));
        """
    }

    /// True when the page shows something the watch could play.
    static let probeVideo = """
    (function() {
      if (/youtube\\.com\\/(watch|shorts|live)|youtu\\.be\\//.test(location.href)) { return true; }
      var vids = document.querySelectorAll('video');
      for (var i = 0; i < vids.length; i++) {
        var r = vids[i].getBoundingClientRect();
        if (r.width >= 120 && r.height >= 68) { return true; }
      }
      return false;
    })();
    """

    /// Finds the page's main video and a URL the watch can stream itself.
    /// Pauses the phone's copy when it hands the video off, so audio doesn't
    /// play in two places.
    static let extractVideo = """
    (function() {
      var out = { title: document.title || '', time: 0, url: null };
      var best = null, bestArea = 0;
      document.querySelectorAll('video').forEach(function(v) {
        var r = v.getBoundingClientRect(); var a = r.width * r.height;
        if (a > bestArea) { bestArea = a; best = v; }
      });
      if (best) {
        out.time = best.currentTime || 0;
        var src = best.currentSrc || best.src || '';
        if (/^https?:/i.test(src)) { out.url = src; }
        if (!out.url) {
          var source = best.querySelector('source[src]');
          if (source && /^https?:/i.test(source.src)) { out.url = source.src; }
        }
      }
      if (!out.url) {
        // YouTube plays through Media Source (blob: URLs). Its player
        // response sometimes lists progressive MP4s (video+audio) or, for
        // live streams, an HLS manifest — both play natively on the watch.
        var pr = null;
        try {
          var player = document.getElementById('movie_player');
          if (player && typeof player.getPlayerResponse === 'function') { pr = player.getPlayerResponse(); }
        } catch (e) {}
        pr = pr || window.ytInitialPlayerResponse || null;
        if (pr && pr.streamingData) {
          var sd = pr.streamingData;
          if (sd.hlsManifestUrl) { out.url = sd.hlsManifestUrl; }
          else {
            var progressive = (sd.formats || []).filter(function(f) {
              return f.url && /video\\/mp4/.test(f.mimeType || '');
            }).sort(function(a, b) { return (a.height || 0) - (b.height || 0); });
            var pick = progressive.filter(function(f) { return (f.height || 0) <= 480; }).pop() || progressive[0];
            if (pick) { out.url = pick.url; }
          }
          if (pr.videoDetails && pr.videoDetails.title) { out.title = pr.videoDetails.title; }
        }
      }
      if (out.url && best) { try { best.pause(); } catch (e) {} }
      return JSON.stringify(out);
    })();
    """

    /// Plays or pauses the page's main video on the phone.
    static func setMainVideoPlaying(_ playing: Bool) -> String {
        """
        (function(play) {
          var best = null, bestArea = 0;
          document.querySelectorAll('video').forEach(function(v) {
            var r = v.getBoundingClientRect(); var a = r.width * r.height;
            if (a > bestArea) { bestArea = a; best = v; }
          });
          if (!best) { return false; }
          try { if (play) { best.play(); } else { best.pause(); } } catch (e) {}
          return true;
        })(\(playing ? "true" : "false"));
        """
    }
}
