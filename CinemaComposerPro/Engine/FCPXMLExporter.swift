import Foundation

/// FCPXML 1.10 — the format Final Cut Pro actually reads.
///
/// The two things naive exporters get wrong are both handled here. First,
/// times are written as exact rationals (`1001/30000s`), not rounded decimals,
/// so a round-trip is lossless. Second, a nested clip's `offset` is expressed
/// in its *parent's* local timeline, whose origin is the parent's own `start`
/// value — not in sequence time. Get that wrong and every connected clip lands
/// in the wrong place the moment a parent is trimmed.
enum FCPXMLExporter {

    // MARK: - Entry point

    static func export(_ timeline: MagneticTimeline, eventName: String = "Cinema Composer Pro") -> String {
        var resources = ResourceTable()
        let formatID = resources.addFormat(timeline.format)

        // Assets must be declared before the spine references them. Walking
        // descendants rather than placed items reaches inside compounds too.
        for item in timeline.spine.flatMap({ $0.selfAndDescendants }) {
            if let ref = item.content.mediaRef {
                resources.addAsset(ref, formatID: formatID, rate: timeline.format.rate)
            }
            if let transition = item.transitionIn { resources.addEffect(transition) }
            if let transition = item.transitionOut { resources.addEffect(transition) }
            if case .title = item.content { resources.addTitleEffect() }
            for effect in item.effects {
                resources.addEffect(id: effect.effectID, name: effect.name)
            }
        }

        var body = ""
        var cursor = RationalTime.zero
        for item in timeline.spine {
            body += node(for: item,
                         offsetInParent: cursor,
                         timeline: timeline,
                         resources: resources,
                         indent: 10)
            cursor += item.duration
        }

        let sequenceDuration = timeline.duration
        let tcFormat = timeline.format.rate.isDropFrame ? "DF" : "NDF"

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.10">
          <resources>
        \(resources.markup(indent: 4))
          </resources>
          <library>
            <event name="\(escape(eventName))">
              <project name="\(escape(timeline.name))">
                <sequence format="\(formatID)" duration="\(sequenceDuration.fcpxmlValue)" \
        tcStart="0s" tcFormat="\(tcFormat)" audioLayout="stereo" audioRate="48k">
                  <spine>
        \(body)          </spine>
                </sequence>
              </project>
            </event>
          </library>
        </fcpxml>
        """
    }

    // MARK: - Items

    private static func node(for item: TimelineItem,
                             offsetInParent: RationalTime,
                             timeline: MagneticTimeline,
                             resources: ResourceTable,
                             indent: Int) -> String {
        let pad = String(repeating: " ", count: indent)

        if item.content.isGap {
            var gap = "\(pad)<gap name=\"Gap\" offset=\"\(offsetInParent.fcpxmlValue)\" "
            gap += "duration=\"\(item.duration.fcpxmlValue)\" start=\"0s\""
            let children = childMarkup(of: item, timeline: timeline, resources: resources, indent: indent + 2)
            if children.isEmpty { return gap + "/>\n" }
            return gap + ">\n" + children + "\(pad)</gap>\n"
        }

        // A compound is a container clip holding its own spine. Emitting it this
        // way keeps the nesting Final Cut expects without having to mint a
        // separate media resource for something that has no asset of its own.
        if case .compound(let nested) = item.content {
            var open = "\(pad)<clip name=\"\(escape(item.name))\" "
            open += "offset=\"\(offsetInParent.fcpxmlValue)\" start=\"\(item.sourceIn.fcpxmlValue)\" "
            open += "duration=\"\(item.duration.fcpxmlValue)\""
            if item.lane != 0 { open += " lane=\"\(item.lane)\"" }
            if !item.isEnabled { open += " enabled=\"0\"" }
            open += ">\n\(pad)  <spine>\n"

            var inner = ""
            var innerCursor = item.sourceIn
            for child in nested {
                inner += node(for: child,
                              offsetInParent: innerCursor,
                              timeline: timeline,
                              resources: resources,
                              indent: indent + 4)
                innerCursor += child.duration
            }
            let trailing = childMarkup(of: item, timeline: timeline, resources: resources, indent: indent + 2)
            return open + inner + "\(pad)  </spine>\n" + trailing + "\(pad)</clip>\n"
        }

        let element: String
        var attributes: [String] = []

        switch item.content {
        case .media(let ref):
            element = "asset-clip"
            attributes.append("ref=\"\(resources.assetID(for: ref))\"")
        case .title:
            element = "title"
            attributes.append("ref=\"\(ResourceTable.titleEffectID)\"")
            attributes.append("role=\"\(escape(item.role.fcpxmlValue))\"")
        case .caption(let caption):
            // Final Cut models captions as their own element with a caption
            // role, which is what keeps them exportable as iTT or SRT later.
            element = "caption"
            attributes.append("role=\"\(escape(captionRole(caption)))\"")
        case .multicam(let multicam):
            // Only the active angles are referenced; the rest stay in the clip
            // so the decision can be revised.
            element = "mc-clip"
            if let video = multicam.activeVideoAngle {
                attributes.append("srcEnable=\"\(multicam.activeAudioAngleID == video.id ? "all" : "video")\"")
            }
        case .compound, .gap:
            element = "gap"
        }

        attributes.append("name=\"\(escape(item.name))\"")
        attributes.append("offset=\"\(offsetInParent.fcpxmlValue)\"")
        attributes.append("start=\"\(item.sourceIn.fcpxmlValue)\"")
        attributes.append("duration=\"\(item.duration.fcpxmlValue)\"")
        if item.lane != 0 { attributes.append("lane=\"\(item.lane)\"") }
        if !item.isEnabled { attributes.append("enabled=\"0\"") }

        if case .media = item.content {
            if item.role.kind == .audio {
                attributes.append("audioRole=\"\(escape(item.role.fcpxmlValue))\"")
            } else {
                attributes.append("videoRole=\"\(escape(item.role.fcpxmlValue))\"")
            }
        }

        let open = "\(pad)<\(element) \(attributes.joined(separator: " "))"
        let children = childMarkup(of: item, timeline: timeline, resources: resources, indent: indent + 2)
        if children.isEmpty { return open + "/>\n" }
        return open + ">\n" + children + "\(pad)</\(element)>\n"
    }

    /// Everything that lives inside a clip element: adjustments, retiming,
    /// markers, keywords, ratings — and the connected clips, whose offsets are
    /// rebased into this clip's local timeline.
    private static func childMarkup(of item: TimelineItem,
                                    timeline: MagneticTimeline,
                                    resources: ResourceTable,
                                    indent: Int) -> String {
        let pad = String(repeating: " ", count: indent)
        var markup = ""

        if case .caption(let caption) = item.content {
            markup += "\(pad)<text>\n"
            for line in caption.text.split(separator: "\n", omittingEmptySubsequences: false) {
                markup += "\(pad)  <text-style>\(escape(String(line)))</text-style>\n"
            }
            markup += "\(pad)</text>\n"
        }
        if case .multicam(let multicam) = item.content {
            for angle in multicam.angles {
                let active = angle.id == multicam.activeVideoAngleID
                markup += "\(pad)<mc-angle name=\"\(escape(angle.name))\" "
                markup += "angleID=\"\(angle.id)\" active=\"\(active ? 1 : 0)\"/>\n"
            }
        }
        if !item.transform.isIdentity {
            markup += transformMarkup(item.transform, pad: pad)
        }
        if !item.color.isNeutral {
            markup += colorMarkup(item.color, pad: pad)
        }
        for effect in item.effects {
            markup += effectMarkup(effect, resources: resources, pad: pad)
        }
        if item.hasAudio || item.audio.volumeDB.constant != 0 || item.audio.volumeDB.isAnimated {
            markup += volumeMarkup(item.audio, pad: pad)
        }
        if let retime = item.retime, retime.isActive {
            markup += timeMapMarkup(retime, item: item, pad: pad)
        }
        if let transition = item.transitionIn {
            markup += "\(pad)<transition name=\"\(escape(transition.name))\" "
            markup += "offset=\"\(item.sourceIn.fcpxmlValue)\" duration=\"\(transition.duration.fcpxmlValue)\">\n"
            markup += "\(pad)  <filter-video ref=\"\(resources.effectID(for: transition))\" name=\"\(escape(transition.name))\"/>\n"
            markup += "\(pad)</transition>\n"
        }

        for marker in item.markers {
            markup += markerMarkup(marker, rate: timeline.format.rate, sourceIn: item.sourceIn, pad: pad)
        }
        for keyword in item.keywords {
            markup += "\(pad)<keyword start=\"\((item.sourceIn + keyword.start).fcpxmlValue)\" "
            markup += "duration=\"\(keyword.duration.fcpxmlValue)\" value=\"\(escape(keyword.name))\"/>\n"
        }
        if let rating = item.rating {
            markup += "\(pad)<rating name=\"\(rating.rawValue)\" "
            markup += "start=\"\(item.sourceIn.fcpxmlValue)\" duration=\"\(item.duration.fcpxmlValue)\"/>\n"
        }
        if !item.notes.isEmpty {
            markup += "\(pad)<note>\(escape(item.notes))</note>\n"
        }

        // A nested clip's offset is measured in the parent's local timeline,
        // which begins at the parent's own `start` — so rebase onto sourceIn.
        for child in item.connected {
            markup += node(for: child,
                           offsetInParent: item.sourceIn + child.offset,
                           timeline: timeline,
                           resources: resources,
                           indent: indent)
        }
        return markup
    }

    // MARK: - Adjustments

    private static func transformMarkup(_ transform: Transform, pad: String) -> String {
        var markup = "\(pad)<adjust-transform "
        markup += "position=\"\(number(transform.positionX.constant)) \(number(transform.positionY.constant))\" "
        markup += "scale=\"\(number(transform.scaleX.constant / 100)) \(number(transform.scaleY.constant / 100))\" "
        markup += "rotation=\"\(number(transform.rotation.constant))\" "
        markup += "anchor=\"\(number(transform.anchorX.constant)) \(number(transform.anchorY.constant))\""

        var params = ""
        params += pairParam(name: "position", x: transform.positionX, y: transform.positionY, pad: pad + "  ")
        params += scalarParam(name: "rotation", value: transform.rotation, pad: pad + "  ")
        params += pairParam(name: "scale", x: transform.scaleX, y: transform.scaleY, scale: 0.01, pad: pad + "  ")

        if params.isEmpty { return markup + "/>\n" }
        return markup + ">\n" + params + "\(pad)</adjust-transform>\n"
    }

    /// Captions carry their language in the role, the way Final Cut names them
    /// (`iTT?captionFormat=ITT.en`), so a multi-language sequence round-trips.
    private static func captionRole(_ caption: CaptionContent) -> String {
        switch caption.format {
        case .itt: return "iTT?captionFormat=ITT.\(caption.language)"
        case .srt: return "SRT?captionFormat=SRT.\(caption.language)"
        case .vtt, .cea608: return "CEA608?captionFormat=CEA608.\(caption.language)"
        }
    }

    /// The grade, written as Final Cut's colour adjustment plus a correction
    /// element carrying the three-way wheels.
    private static func colorMarkup(_ color: ColorCorrection, pad: String) -> String {
        var markup = "\(pad)<adjust-color "
        markup += "saturation=\"\(number(color.saturation.constant / 100))\" "
        markup += "exposure=\"\(number(color.exposure.constant))\" "
        markup += "contrast=\"\(number(color.contrast.constant))\" "
        markup += "enabled=\"\(color.isEnabled ? 1 : 0)\""

        var inner = ""
        inner += wheelMarkup("master", color.master, pad: pad + "  ")
        inner += wheelMarkup("shadows", color.shadows, pad: pad + "  ")
        inner += wheelMarkup("midtones", color.midtones, pad: pad + "  ")
        inner += wheelMarkup("highlights", color.highlights, pad: pad + "  ")
        inner += scalarParam(name: "saturation", value: color.saturation, pad: pad + "  ")
        inner += scalarParam(name: "exposure", value: color.exposure, pad: pad + "  ")
        inner += scalarParam(name: "contrast", value: color.contrast, pad: pad + "  ")

        if !color.luma.isIdentity {
            inner += "\(pad)  <param name=\"lumaCurve\">\n"
            for point in color.luma.points.sorted(by: { $0.input < $1.input }) {
                inner += "\(pad)    <point x=\"\(number(point.input))\" y=\"\(number(point.output))\"/>\n"
            }
            inner += "\(pad)  </param>\n"
        }
        if !color.lutName.isEmpty {
            inner += "\(pad)  <param name=\"lut\" value=\"\(escape(color.lutName))\"/>\n"
        }

        if inner.isEmpty { return markup + "/>\n" }
        return markup + ">\n" + inner + "\(pad)</adjust-color>\n"
    }

    private static func wheelMarkup(_ name: String, _ wheel: ColorWheel, pad: String) -> String {
        guard !wheel.isNeutral else { return "" }
        return "\(pad)<param name=\"\(name)\" "
            + "hue=\"\(number(wheel.hueAngle.constant))\" "
            + "sat=\"\(number(wheel.saturation.constant))\" "
            + "bright=\"\(number(wheel.brightness.constant))\"/>\n"
    }

    private static func effectMarkup(_ effect: Effect,
                                     resources: ResourceTable,
                                     pad: String) -> String {
        let element = effect.category == .audio ? "filter-audio" : "filter-video"
        var markup = "\(pad)<\(element) ref=\"\(resources.effectID(forEffectID: effect.effectID))\" "
        markup += "name=\"\(escape(effect.name))\""
        if !effect.isEnabled { markup += " enabled=\"0\"" }

        var params = ""
        for parameter in effect.parameters {
            switch parameter.value {
            case .number(let animatable):
                if animatable.isAnimated {
                    params += scalarParam(name: parameter.name, value: animatable, pad: pad + "  ")
                } else {
                    params += "\(pad)  <param name=\"\(escape(parameter.name))\" "
                    params += "value=\"\(number(animatable.constant))\"/>\n"
                }
            case .toggle(let on):
                params += "\(pad)  <param name=\"\(escape(parameter.name))\" value=\"\(on ? 1 : 0)\"/>\n"
            case .choice(let index, let options):
                let label = options.indices.contains(index) ? options[index] : ""
                params += "\(pad)  <param name=\"\(escape(parameter.name))\" "
                params += "value=\"\(index)\" key=\"\(escape(label))\"/>\n"
            case .text(let value):
                params += "\(pad)  <param name=\"\(escape(parameter.name))\" "
                params += "value=\"\(escape(value))\"/>\n"
            case .color(let red, let green, let blue):
                params += "\(pad)  <param name=\"\(escape(parameter.name))\" "
                params += "value=\"\(number(red.constant)) \(number(green.constant)) \(number(blue.constant))\"/>\n"
            }
        }
        if params.isEmpty { return markup + "/>\n" }
        return markup + ">\n" + params + "\(pad)</\(element)>\n"
    }

    private static func volumeMarkup(_ audio: AudioSettings, pad: String) -> String {
        let amount = audio.isMuted ? -96 : audio.volumeDB.constant
        var markup = "\(pad)<adjust-volume amount=\"\(number(amount))dB\""
        let params = dbParam(name: "amount", value: audio.volumeDB, pad: pad + "  ")
        if params.isEmpty { return markup + "/>\n" }
        markup += ">\n" + params + "\(pad)</adjust-volume>\n"
        return markup
    }

    /// A time map expresses retiming as a curve from timeline time to source
    /// time — which is exactly how Final Cut stores speed changes and ramps.
    private static func timeMapMarkup(_ retime: Retime, item: TimelineItem, pad: String) -> String {
        var markup = "\(pad)<timeMap frameSampling=\"floor\">\n"
        var timelineCursor = RationalTime.zero
        var sourceCursor = item.sourceIn
        markup += "\(pad)  <timept time=\"0s\" value=\"\(sourceCursor.fcpxmlValue)\" interp=\"linear\"/>\n"
        for segment in retime.segments {
            timelineCursor += segment.timelineDuration
            sourceCursor += (segment.sourceEnd - segment.sourceStart)
            let interp = segment.kind == .ramp ? "smooth2" : "linear"
            markup += "\(pad)  <timept time=\"\(timelineCursor.fcpxmlValue)\" "
            markup += "value=\"\(sourceCursor.fcpxmlValue)\" interp=\"\(interp)\"/>\n"
        }
        markup += "\(pad)</timeMap>\n"
        return markup
    }

    private static func markerMarkup(_ marker: EditMarker,
                                     rate: FrameRate,
                                     sourceIn: RationalTime,
                                     pad: String) -> String {
        let start = (sourceIn + marker.at).fcpxmlValue
        let duration = marker.duration.isZero ? rate.frameDuration : marker.duration
        switch marker.kind {
        case .chapter:
            return "\(pad)<chapter-marker start=\"\(start)\" duration=\"\(duration.fcpxmlValue)\" "
                + "value=\"\(escape(marker.name))\" posterOffset=\"0s\"/>\n"
        case .toDo:
            return "\(pad)<marker start=\"\(start)\" duration=\"\(duration.fcpxmlValue)\" "
                + "value=\"\(escape(marker.name))\" completed=\"0\"/>\n"
        case .completed:
            return "\(pad)<marker start=\"\(start)\" duration=\"\(duration.fcpxmlValue)\" "
                + "value=\"\(escape(marker.name))\" completed=\"1\"/>\n"
        case .standard:
            return "\(pad)<marker start=\"\(start)\" duration=\"\(duration.fcpxmlValue)\" "
                + "value=\"\(escape(marker.name))\"/>\n"
        }
    }

    // MARK: - Keyframe params

    private static func scalarParam(name: String, value: AnimatableValue, pad: String) -> String {
        guard value.isAnimated else { return "" }
        var markup = "\(pad)<param name=\"\(name)\">\n\(pad)  <keyframeAnimation>\n"
        for keyframe in value.keyframes.sorted(by: { $0.time < $1.time }) {
            markup += "\(pad)    <keyframe time=\"\(keyframe.time.fcpxmlValue)\" "
            markup += "value=\"\(number(keyframe.value))\" interp=\"\(interp(keyframe.interpolation))\"/>\n"
        }
        return markup + "\(pad)  </keyframeAnimation>\n\(pad)</param>\n"
    }

    private static func dbParam(name: String, value: AnimatableValue, pad: String) -> String {
        guard value.isAnimated else { return "" }
        var markup = "\(pad)<param name=\"\(name)\">\n\(pad)  <keyframeAnimation>\n"
        for keyframe in value.keyframes.sorted(by: { $0.time < $1.time }) {
            markup += "\(pad)    <keyframe time=\"\(keyframe.time.fcpxmlValue)\" "
            markup += "value=\"\(number(keyframe.value))dB\" interp=\"\(interp(keyframe.interpolation))\"/>\n"
        }
        return markup + "\(pad)  </keyframeAnimation>\n\(pad)</param>\n"
    }

    /// Position and scale are 2-vectors in FCPXML, so their keyframes have to be
    /// emitted as a single interleaved track rather than two independent ones.
    private static func pairParam(name: String,
                                  x: AnimatableValue,
                                  y: AnimatableValue,
                                  scale: Double = 1,
                                  pad: String) -> String {
        guard x.isAnimated || y.isAnimated else { return "" }
        var times: [RationalTime] = x.keyframes.map(\.time) + y.keyframes.map(\.time)
        times = Array(Set(times)).sorted()
        guard !times.isEmpty else { return "" }

        var markup = "\(pad)<param name=\"\(name)\">\n\(pad)  <keyframeAnimation>\n"
        for time in times {
            let vx = x.value(at: time) * scale
            let vy = y.value(at: time) * scale
            markup += "\(pad)    <keyframe time=\"\(time.fcpxmlValue)\" "
            markup += "value=\"\(number(vx)) \(number(vy))\"/>\n"
        }
        return markup + "\(pad)  </keyframeAnimation>\n\(pad)</param>\n"
    }

    private static func interp(_ interpolation: Interpolation) -> String {
        switch interpolation {
        case .linear: return "linear"
        case .ease: return "smooth2"
        case .easeIn: return "easeIn"
        case .easeOut: return "easeOut"
        case .hold: return "hold"
        }
    }

    // MARK: - Helpers

    private static func number(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e9 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.4f", value)
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

/// Resource ids have to be stable and declared up front, so they are minted once
/// and looked up by asset rather than regenerated per reference.
private struct ResourceTable {
    static let titleEffectID = "r_title"

    private var formatMarkup: String = ""
    private let formatIdentifier: String = "r1"
    private var assetIDs: [String: String] = [:]
    private var assetMarkup: [String] = []
    private var effectIDs: [String: String] = [:]
    private var effectMarkup: [String] = []
    private var includesTitle = false
    private var nextIndex = 2

    mutating func addFormat(_ format: TimelineFormat) -> String {
        let name = "FFVideoFormat\(format.resolution.height)p\(format.rate.nominalRate)"
        formatMarkup = "<format id=\"r1\" name=\"\(name)\" "
            + "frameDuration=\"\(format.rate.frameDuration.fcpxmlValue)\" "
            + "width=\"\(format.resolution.width)\" height=\"\(format.resolution.height)\" "
            + "colorSpace=\"1-1-1 (\(FCPXMLExporter.escape(format.colorSpace)))\"/>"
        return formatIdentifier
    }

    mutating func addAsset(_ ref: MediaRef, formatID: String, rate: FrameRate) {
        guard assetIDs[ref.assetID] == nil else { return }
        let identifier = "r\(nextIndex)"
        nextIndex += 1
        assetIDs[ref.assetID] = identifier

        // Generated media has no file yet; declaring a duration of one frame
        // keeps the document valid without inventing a length it does not have.
        let declared = ref.sourceDuration.isZero ? rate.frameDuration : ref.sourceDuration
        var markup = "<asset id=\"\(identifier)\" name=\"\(FCPXMLExporter.escape(ref.name))\" "
        markup += "start=\"0s\" duration=\"\(declared.fcpxmlValue)\" "
        markup += "hasVideo=\"\(ref.hasVideo ? 1 : 0)\" hasAudio=\"\(ref.hasAudio ? 1 : 0)\" "
        markup += "format=\"\(formatID)\""
        if let url = ref.url, !url.isEmpty {
            markup += ">\n      <media-rep kind=\"original-media\" src=\"\(FCPXMLExporter.escape(url))\"/>\n    </asset>"
        } else {
            markup += "/>"
        }
        assetMarkup.append(markup)
    }

    mutating func addEffect(_ transition: EditTransition) {
        guard effectIDs[transition.effectID] == nil else { return }
        let identifier = "r\(nextIndex)"
        nextIndex += 1
        effectIDs[transition.effectID] = identifier
        effectMarkup.append("<effect id=\"\(identifier)\" name=\"\(FCPXMLExporter.escape(transition.name))\" "
                            + "uid=\"\(transition.effectID)\"/>")
    }

    /// Effects from a clip's stack get a resource of their own, keyed by the
    /// vendor effect id so one entry serves every clip that uses it.
    mutating func addEffect(id effectID: String, name: String) {
        guard effectIDs[effectID] == nil else { return }
        let identifier = "r\(nextIndex)"
        nextIndex += 1
        effectIDs[effectID] = identifier
        effectMarkup.append("<effect id=\"\(identifier)\" name=\"\(FCPXMLExporter.escape(name))\" "
                            + "uid=\"\(FCPXMLExporter.escape(effectID))\"/>")
    }

    func effectID(forEffectID effectID: String) -> String { effectIDs[effectID] ?? "r1" }

    mutating func addTitleEffect() {
        guard !includesTitle else { return }
        includesTitle = true
        effectMarkup.append("<effect id=\"\(Self.titleEffectID)\" name=\"Basic Title\" "
                            + "uid=\".../Titles.localized/Build In:Out.localized/Basic Title.localized/Basic Title.moti\"/>")
    }

    func assetID(for ref: MediaRef) -> String { assetIDs[ref.assetID] ?? "r1" }

    func effectID(for transition: EditTransition) -> String { effectIDs[transition.effectID] ?? "r1" }

    func markup(indent: Int) -> String {
        let pad = String(repeating: " ", count: indent)
        var lines = [pad + formatMarkup]
        lines.append(contentsOf: assetMarkup.map { pad + $0 })
        lines.append(contentsOf: effectMarkup.map { pad + $0 })
        return lines.joined(separator: "\n")
    }
}
