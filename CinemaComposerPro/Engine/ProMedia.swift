import Foundation

// MARK: - Captions

enum CaptionFormat: String, Codable, CaseIterable, Identifiable {
    case itt, srt, vtt, cea608

    var id: String { rawValue }

    var label: String {
        switch self {
        case .itt: return "iTT (iTunes Timed Text)"
        case .srt: return "SubRip (.srt)"
        case .vtt: return "WebVTT (.vtt)"
        case .cea608: return "CEA-608 (broadcast)"
        }
    }

    var fileExtension: String {
        switch self {
        case .itt: return "itt"
        case .srt: return "srt"
        case .vtt: return "vtt"
        case .cea608: return "scc"
        }
    }
}

enum CaptionPlacement: String, Codable, CaseIterable, Identifiable {
    case bottom, top, left, right

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// A caption. Captions are timeline items like any other, so they ripple with
/// the picture instead of living in a sidecar that drifts out of sync the first
/// time somebody trims a shot.
struct CaptionContent: Codable, Equatable {
    var text: String
    var format: CaptionFormat = .itt
    var placement: CaptionPlacement = .bottom
    /// BCP-47, e.g. "en-GB". One sequence can carry several languages at once.
    var language: String = "en"
    var isForced: Bool = false

    /// Captions are read aloud at roughly 3 words a second; anything far past
    /// that is unreadable and worth flagging to the editor.
    func readingRateWarning(duration: RationalTime) -> String? {
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
        let seconds = duration.seconds
        guard seconds > 0, words > 0 else { return nil }
        let rate = Double(words) / seconds
        if rate > 3.5 { return String(format: "%.1f words/sec — too fast to read", rate) }
        if text.count > 84 { return "Over 84 characters — split across two captions" }
        return nil
    }
}

/// Writes a sequence's captions out in the formats a distributor actually asks
/// for. Timecodes come from exact rational time, so nothing drifts.
enum CaptionExporter {

    struct Entry {
        var index: Int
        var start: RationalTime
        var end: RationalTime
        var caption: CaptionContent
    }

    static func entries(from timeline: MagneticTimeline, language: String? = nil) -> [Entry] {
        var found: [Entry] = []
        for placed in timeline.placedItems.sorted(by: { $0.start < $1.start }) {
            guard case .caption(let caption) = placed.item.content else { continue }
            if let language, caption.language != language { continue }
            found.append(Entry(index: found.count + 1,
                               start: placed.start,
                               end: placed.end,
                               caption: caption))
        }
        return found
    }

    static func languages(in timeline: MagneticTimeline) -> [String] {
        var seen: [String] = []
        for placed in timeline.placedItems {
            guard case .caption(let caption) = placed.item.content else { continue }
            if !seen.contains(caption.language) { seen.append(caption.language) }
        }
        return seen.sorted()
    }

    static func export(_ timeline: MagneticTimeline,
                       format: CaptionFormat,
                       language: String? = nil) -> String {
        let rows = entries(from: timeline, language: language)
        switch format {
        case .srt: return srt(rows, rate: timeline.rate)
        case .vtt: return vtt(rows, rate: timeline.rate)
        case .itt, .cea608: return itt(rows, rate: timeline.rate,
                                       language: language ?? rows.first?.caption.language ?? "en")
        }
    }

    // MARK: Formats

    private static func srt(_ rows: [Entry], rate: FrameRate) -> String {
        rows.map { row in
            """
            \(row.index)
            \(clock(row.start, separator: ",")) --> \(clock(row.end, separator: ","))
            \(row.caption.text)
            """
        }.joined(separator: "\n\n") + "\n"
    }

    private static func vtt(_ rows: [Entry], rate: FrameRate) -> String {
        let body = rows.map { row in
            """
            \(row.index)
            \(clock(row.start, separator: ".")) --> \(clock(row.end, separator: "."))\(cueSettings(row.caption))
            \(row.caption.text)
            """
        }.joined(separator: "\n\n")
        return "WEBVTT\n\n" + body + "\n"
    }

    private static func cueSettings(_ caption: CaptionContent) -> String {
        switch caption.placement {
        case .bottom: return ""
        case .top: return " line:5%"
        case .left: return " align:start"
        case .right: return " align:end"
        }
    }

    /// iTT is TTML with Apple's conventions — the format Final Cut round-trips
    /// and the one the iTunes Store requires.
    private static func itt(_ rows: [Entry], rate: FrameRate, language: String) -> String {
        let body = rows.map { row in
            let region = row.caption.placement == .top ? "top" : "bottom"
            return "        <p begin=\"\(timecodeAttribute(row.start, rate: rate))\" "
                + "end=\"\(timecodeAttribute(row.end, rate: rate))\" region=\"\(region)\">"
                + escape(row.caption.text).replacingOccurrences(of: "\n", with: "<br/>")
                + "</p>"
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <tt xmlns="http://www.w3.org/ns/ttml" \
        xmlns:tts="http://www.w3.org/ns/ttml#styling" \
        xmlns:ttp="http://www.w3.org/ns/ttml#parameter" \
        xml:lang="\(language)" ttp:timeBase="smpte" ttp:frameRate="\(rate.nominalRate)" \
        ttp:dropMode="\(rate.isDropFrame ? "dropNTSC" : "nonDrop")">
          <head>
            <layout>
              <region xml:id="bottom" tts:origin="10% 80%" tts:extent="80% 20%" tts:textAlign="center"/>
              <region xml:id="top" tts:origin="10% 0%" tts:extent="80% 20%" tts:textAlign="center"/>
            </layout>
          </head>
          <body>
            <div>
        \(body)
            </div>
          </body>
        </tt>
        """
    }

    // MARK: Helpers

    /// `HH:MM:SS,mmm` for SRT and `HH:MM:SS.mmm` for VTT.
    private static func clock(_ time: RationalTime, separator: String) -> String {
        let total = Swift.max(0, time.seconds)
        let hours = Int(total / 3600)
        let minutes = Int(total / 60) % 60
        let seconds = Int(total) % 60
        let milliseconds = Int(((total - total.rounded(.down)) * 1000).rounded())
        return String(format: "%02d:%02d:%02d%@%03d",
                      hours, minutes, seconds, separator, Swift.min(milliseconds, 999))
    }

    private static func timecodeAttribute(_ time: RationalTime, rate: FrameRate) -> String {
        time.timecode(at: rate)
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - Multicam

/// One angle of a multicam clip: its own little sequence of media.
struct MulticamAngle: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var items: [TimelineItem] = []
    /// Offset applied when syncing this angle against the others.
    var syncOffset: RationalTime = .zero

    var duration: RationalTime {
        items.reduce(RationalTime.zero) { $0 + $1.duration }
    }
}

/// A multicam clip. Cutting between angles is an edit on the *active angle*,
/// which means every angle stays available and a cut can be revised later
/// without re-conforming anything.
struct MulticamContent: Codable, Equatable {
    var angles: [MulticamAngle] = []
    var activeVideoAngleID: String?
    var activeAudioAngleID: String?

    var activeVideoAngle: MulticamAngle? {
        angles.first { $0.id == activeVideoAngleID } ?? angles.first
    }

    var activeAudioAngle: MulticamAngle? {
        angles.first { $0.id == activeAudioAngleID } ?? activeVideoAngle
    }

    /// Longest angle — a multicam clip is as long as its longest source.
    var duration: RationalTime {
        angles.reduce(RationalTime.zero) { RationalTime.max($0, $1.duration) }
    }

    /// Sync every angle against a chosen reference using its stated offset.
    mutating func sync(to referenceID: String) {
        guard let reference = angles.first(where: { $0.id == referenceID }) else { return }
        let base = reference.syncOffset
        for index in angles.indices {
            angles[index].syncOffset = angles[index].syncOffset - base
        }
    }
}

// MARK: - Keyword and smart collections

/// A saved query over the sequence. Final Cut keeps smart collections in the
/// browser; keeping them against the timeline means "every unrated VFX shot
/// over four seconds" is one tap while you are cutting.
struct SmartCollection: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var roleName: String?
    var keyword: String?
    var rating: Rating?
    var textContains: String?
    var minimumSeconds: Double?
    var maximumSeconds: Double?
    var onlyRetimed: Bool = false
    var onlyWithEffects: Bool = false
    var onlyMissingMedia: Bool = false

    func matches(_ placed: PlacedItem) -> Bool {
        let item = placed.item
        if let roleName, item.role.name != roleName { return false }
        if let rating, item.rating != rating { return false }
        if let keyword, !item.keywords.contains(where: { $0.name.localizedCaseInsensitiveContains(keyword) }) {
            return false
        }
        if let textContains, !textContains.isEmpty {
            let haystack = item.name + " " + item.notes + " " + (item.provenance.prompt ?? "")
            if !haystack.localizedCaseInsensitiveContains(textContains) { return false }
        }
        if let minimumSeconds, item.duration.seconds < minimumSeconds { return false }
        if let maximumSeconds, item.duration.seconds > maximumSeconds { return false }
        if onlyRetimed, item.retime == nil { return false }
        if onlyWithEffects, item.effects.isEmpty, item.color.isNeutral { return false }
        if onlyMissingMedia, item.content.mediaRef?.url?.isEmpty == false { return false }
        return true
    }

    static let unratedVFX = SmartCollection(name: "Unrated hero shots",
                                            roleName: "Video",
                                            minimumSeconds: 4)
    static let rejected = SmartCollection(name: "Rejected", rating: .rejected)
    static let retimed = SmartCollection(name: "Retimed", onlyRetimed: true)
    static let graded = SmartCollection(name: "Has effects or grade", onlyWithEffects: true)

    static let starters: [SmartCollection] = [.rejected, .retimed, .graded]
}
