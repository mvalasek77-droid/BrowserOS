import Foundation

/// A take: one generation of one shot, with what it cost. Clips keep their
/// whole take stack, which is what makes the cut a cost document as well as an
/// edit — swapping takes moves money.
struct Take: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var toolID: String
    var cost: Double
    var prompt: String?
    var quality: Double?
    var createdAt: Date = Date()
}

struct Provenance: Codable, Equatable {
    var takeID: String?
    var toolID: String?
    var cost: Double = 0
    var prompt: String?
}

struct Transition: Codable, Equatable {
    var type: String = "dissolve"
    var duration: Double = 0.5
}

struct Clip: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var start: Double
    var duration: Double
    var sourceIn: Double = 0
    var sourceOut: Double = 0
    var shotID: String?
    var isEnabled: Bool = true
    var isLocked: Bool = false
    var transitionIn: Transition?
    var takes: [Take] = []
    var provenance: Provenance = Provenance()

    var end: Double { start + duration }
}

enum TrackKind: String, Codable { case video, audio }

struct Track: Codable, Identifiable, Equatable {
    var id: String
    var kind: TrackKind
    var clips: [Clip] = []
}

struct Marker: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var at: Double
    var name: String
    var note: String = ""
}

enum TimelineError: LocalizedError {
    case noSuchClip(String)
    case noSuchTrack(String)
    case noSuchTake(String)
    case bladeOutsideClip
    case trimConsumesClip
    case nonPositiveDuration

    var errorDescription: String? {
        switch self {
        case .noSuchClip(let id): return "No clip \(id) in this sequence"
        case .noSuchTrack(let id): return "No track \(id) in this sequence"
        case .noSuchTake(let id): return "No take \(id) on this clip"
        case .bladeOutsideClip: return "The blade point is outside the clip"
        case .trimConsumesClip: return "That trim would consume the whole clip"
        case .nonPositiveDuration: return "A clip needs a positive duration"
        }
    }
}

/// The cutting room. A real NLE model — insert, overwrite, blade, ripple, slip —
/// plus the thing a traditional NLE cannot have: every clip knows which tool
/// generated it, from which prompt, at what cost. So a trim is a budget event,
/// and "regenerate this shot" is a first-class edit.
struct Timeline: Codable, Equatable {
    var name: String = "Sequence 1"
    var fps: Double = 24
    var resolution: Resolution = Resolution(width: 1920, height: 1080)
    var tracks: [Track] = [
        Track(id: "V1", kind: .video),
        Track(id: "A1", kind: .audio),
        Track(id: "A2", kind: .audio),
    ]
    var markers: [Marker] = []

    // MARK: - Reading

    var allClips: [Clip] { tracks.flatMap(\.clips) }

    var duration: Double { allClips.map(\.end).max() ?? 0 }

    var clipCount: Int { allClips.count }

    /// What the current cut cost to generate — only clips actually on the
    /// timeline count.
    var costOfCut: Double { allClips.reduce(0) { $0 + $1.provenance.cost } }

    /// Money spent on takes that did not make the cut: the AI era's wasted footage.
    var costOfUnusedTakes: Double {
        allClips.reduce(0) { running, clip in
            running + clip.takes.filter { $0.id != clip.provenance.takeID }.reduce(0) { $0 + $1.cost }
        }
    }

    func trackID(of clipID: String) -> String? {
        tracks.first { $0.clips.contains { $0.id == clipID } }?.id
    }

    func clip(_ clipID: String) -> Clip? {
        for track in tracks {
            if let clip = track.clips.first(where: { $0.id == clipID }) { return clip }
        }
        return nil
    }

    private func locate(_ clipID: String) throws -> (track: Int, clip: Int) {
        for (t, track) in tracks.enumerated() {
            if let c = track.clips.firstIndex(where: { $0.id == clipID }) { return (t, c) }
        }
        throw TimelineError.noSuchClip(clipID)
    }

    private func trackIndex(_ trackID: String) throws -> Int {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { throw TimelineError.noSuchTrack(trackID) }
        return index
    }

    // MARK: - Building

    @discardableResult
    mutating func addTrack(kind: TrackKind) -> String {
        let count = tracks.filter { $0.kind == kind }.count + 1
        let id = "\(kind == .video ? "V" : "A")\(count)"
        tracks.append(Track(id: id, kind: kind))
        return id
    }

    /// Place at the end of a track — the fastest way to build an assembly.
    @discardableResult
    mutating func append(_ clip: Clip, to trackID: String) throws -> Clip {
        let index = try trackIndex(trackID)
        var placed = normalize(clip)
        placed.start = tracks[index].clips.last?.end ?? 0
        guard placed.duration > 0 else { throw TimelineError.nonPositiveDuration }
        tracks[index].clips.append(placed)
        return placed
    }

    /// Insert at a point, pushing everything downstream later.
    @discardableResult
    mutating func insert(_ clip: Clip, into trackID: String, at position: Double) throws -> Clip {
        let index = try trackIndex(trackID)
        var placed = normalize(clip)
        placed.start = position
        guard placed.duration > 0 else { throw TimelineError.nonPositiveDuration }
        for i in tracks[index].clips.indices where tracks[index].clips[i].start >= position - 1e-9 {
            tracks[index].clips[i].start += placed.duration
        }
        tracks[index].clips.append(placed)
        sort(track: index)
        return placed
    }

    /// Drop on top, trimming or removing whatever it lands on. Nothing moves.
    @discardableResult
    mutating func overwrite(_ clip: Clip, into trackID: String, at position: Double) throws -> Clip {
        let index = try trackIndex(trackID)
        var placed = normalize(clip)
        placed.start = position
        guard placed.duration > 0 else { throw TimelineError.nonPositiveDuration }
        let end = placed.end

        var kept: [Clip] = []
        for var existing in tracks[index].clips {
            if existing.end <= placed.start || existing.start >= end {
                kept.append(existing)
                continue
            }
            if existing.start < placed.start && existing.end > end {
                // Split around the incoming clip.
                var tail = existing
                tail.id = UUID().uuidString
                tail.sourceIn = existing.sourceIn + (end - existing.start)
                tail.start = end
                tail.duration = existing.end - end
                tail.sourceOut = tail.sourceIn + tail.duration

                existing.duration = placed.start - existing.start
                existing.sourceOut = existing.sourceIn + existing.duration
                kept.append(existing)
                kept.append(tail)
            } else if existing.start < placed.start {
                existing.duration = placed.start - existing.start
                existing.sourceOut = existing.sourceIn + existing.duration
                kept.append(existing)
            } else if existing.end > end {
                existing.sourceIn += end - existing.start
                existing.duration = existing.end - end
                existing.start = end
                existing.sourceOut = existing.sourceIn + existing.duration
                kept.append(existing)
            }
            // Fully covered clips are dropped.
        }
        kept.append(placed)
        tracks[index].clips = kept.filter { $0.duration > 1e-6 }
        sort(track: index)
        return placed
    }

    // MARK: - Editing

    @discardableResult
    mutating func blade(_ clipID: String, at position: Double) throws -> [Clip] {
        let at = try locate(clipID)
        let clip = tracks[at.track].clips[at.clip]
        guard position > clip.start + 1e-9, position < clip.end - 1e-9 else { throw TimelineError.bladeOutsideClip }

        let offset = position - clip.start
        var tail = clip
        tail.id = UUID().uuidString
        tail.start = position
        tail.duration = clip.duration - offset
        tail.sourceIn = clip.sourceIn + offset
        tail.sourceOut = clip.sourceOut

        tracks[at.track].clips[at.clip].duration = offset
        tracks[at.track].clips[at.clip].sourceOut = clip.sourceIn + offset
        tracks[at.track].clips.append(tail)
        sort(track: at.track)
        return [tracks[at.track].clips[at.clip], tail]
    }

    /// Remove and close the gap.
    @discardableResult
    mutating func rippleDelete(_ clipID: String) throws -> Clip {
        let at = try locate(clipID)
        let removed = tracks[at.track].clips.remove(at: at.clip)
        for i in tracks[at.track].clips.indices where tracks[at.track].clips[i].start > removed.start {
            tracks[at.track].clips[i].start -= removed.duration
        }
        return removed
    }

    /// Remove and leave the hole.
    @discardableResult
    mutating func lift(_ clipID: String) throws -> Clip {
        let at = try locate(clipID)
        return tracks[at.track].clips.remove(at: at.clip)
    }

    /// Trim an edge. `ripple` closes the gap the trim opens.
    @discardableResult
    mutating func trim(_ clipID: String, head: Double = 0, tail: Double = 0, ripple: Bool = true) throws -> Clip {
        let at = try locate(clipID)
        var clip = tracks[at.track].clips[at.clip]
        let newDuration = clip.duration - head - tail
        guard newDuration > 0 else { throw TimelineError.trimConsumesClip }

        let originalStart = clip.start
        clip.sourceIn += head
        clip.duration = newDuration
        clip.sourceOut = clip.sourceIn + newDuration
        if !ripple { clip.start += head }
        tracks[at.track].clips[at.clip] = clip

        if ripple {
            let shift = head + tail
            for i in tracks[at.track].clips.indices where tracks[at.track].clips[i].start > originalStart {
                tracks[at.track].clips[i].start -= shift
            }
        }
        sort(track: at.track)
        return tracks[at.track].clips.first { $0.id == clipID } ?? clip
    }

    /// Slide the source window without moving the clip in the timeline.
    @discardableResult
    mutating func slip(_ clipID: String, by delta: Double) throws -> Clip {
        let at = try locate(clipID)
        tracks[at.track].clips[at.clip].sourceIn = max(0, tracks[at.track].clips[at.clip].sourceIn + delta)
        tracks[at.track].clips[at.clip].sourceOut = tracks[at.track].clips[at.clip].sourceIn + tracks[at.track].clips[at.clip].duration
        return tracks[at.track].clips[at.clip]
    }

    mutating func setTransition(_ clipID: String, transition: Transition?) throws {
        let at = try locate(clipID)
        tracks[at.track].clips[at.clip].transitionIn = transition
    }

    @discardableResult
    mutating func addMarker(at position: Double, name: String, note: String = "") -> Marker {
        let marker = Marker(at: position, name: name, note: note)
        markers.append(marker)
        markers.sort { $0.at < $1.at }
        return marker
    }

    // MARK: - Takes

    @discardableResult
    mutating func addTake(_ take: Take, to clipID: String, select: Bool = true) throws -> Take {
        let at = try locate(clipID)
        tracks[at.track].clips[at.clip].takes.append(take)
        if select {
            tracks[at.track].clips[at.clip].provenance = Provenance(takeID: take.id, toolID: take.toolID, cost: take.cost, prompt: take.prompt)
        }
        return take
    }

    mutating func selectTake(_ takeID: String, on clipID: String) throws {
        let at = try locate(clipID)
        guard let take = tracks[at.track].clips[at.clip].takes.first(where: { $0.id == takeID }) else {
            throw TimelineError.noSuchTake(takeID)
        }
        tracks[at.track].clips[at.clip].provenance = Provenance(takeID: take.id, toolID: take.toolID, cost: take.cost, prompt: take.prompt)
    }

    /// The AI-native edit: hand this back to the conductor and exactly this clip
    /// is re-rendered — same slot, same length — on a different tool or prompt.
    func regenerationTask(for clipID: String, toolID: String, tool: AITool?, prompt: String? = nil) throws -> PlanTask {
        guard let clip = clip(clipID) else { throw TimelineError.noSuchClip(clipID) }
        let units = clip.duration
        return PlanTask(
            id: "regen.\(clip.id)",
            department: .photography,
            label: "Regenerate \(clip.name)",
            capability: Capability.videoTextToVideo,
            toolID: toolID,
            units: units,
            unitLabel: "video seconds",
            billableUnits: tool?.billableUnits(for: units) ?? units,
            cost: tool?.estimatedCost(units: units) ?? 0,
            workerSeconds: tool?.estimatedSeconds(units: units) ?? units,
            concurrency: 1,
            dependsOn: [],
            shotCount: 1,
            prompt: prompt ?? clip.provenance.prompt ?? clip.name
        )
    }

    // MARK: - Housekeeping

    /// Overlaps and negative times are editor bugs, not user errors.
    func validate() -> [String] {
        var problems: [String] = []
        for track in tracks {
            let sorted = track.clips.sorted { $0.start < $1.start }
            for (index, clip) in sorted.enumerated() {
                if clip.start < -1e-9 { problems.append("\(clip.name) starts before zero") }
                if clip.duration <= 0 { problems.append("\(clip.name) has no duration") }
                if index + 1 < sorted.count, clip.end > sorted[index + 1].start + 1e-6 {
                    problems.append("\(clip.name) overlaps \(sorted[index + 1].name) on \(track.id)")
                }
            }
        }
        return problems
    }

    private func normalize(_ clip: Clip) -> Clip {
        var copy = clip
        if copy.sourceOut <= copy.sourceIn { copy.sourceOut = copy.sourceIn + copy.duration }
        return copy
    }

    private mutating func sort(track index: Int) {
        tracks[index].clips.sort { $0.start < $1.start }
    }

    // MARK: - Assembly

    /// Seed a first cut straight from the breakdown: every shot becomes a clip
    /// carrying the cost the plan says it will incur, dialogue shots get an A1
    /// slot, and the score lands on A2.
    static func assembly(from breakdown: Breakdown, plan: ProductionPlan) -> Timeline {
        var timeline = Timeline(name: "\(breakdown.spec.title) — Assembly",
                                fps: breakdown.spec.fps,
                                resolution: breakdown.spec.tier.resolution)

        let finals = plan.tasks(in: .photography).filter { !$0.isExplorationPass }
        let photographyCost = plan.tasks(in: .photography).reduce(0) { $0 + $1.cost }
        let perSecond = breakdown.runtimeSeconds <= 0 ? 0 : photographyCost / breakdown.runtimeSeconds
        let heroTool = finals.first { $0.id.contains("hero") }?.toolID ?? finals.first?.toolID ?? "unassigned"
        let bodyTool = finals.first { $0.id.contains("body") }?.toolID ?? heroTool

        for shot in breakdown.shots {
            let toolID = shot.needsHeroGenerator ? heroTool : bodyTool
            let cost = shot.seconds * perSecond
            let prompt = "\(breakdown.spec.style) — scene \(shot.scene)"
            var clip = Clip(name: shot.id, start: 0, duration: shot.seconds, shotID: shot.id)
            clip.provenance = Provenance(takeID: nil, toolID: toolID, cost: cost, prompt: prompt)
            if let placed = try? timeline.append(clip, to: "V1") {
                try? timeline.addTake(Take(toolID: toolID, cost: cost, prompt: prompt), to: placed.id)
            }
            if shot.hasDialogue {
                var dialogue = Clip(name: "\(shot.id) DX", start: 0, duration: shot.seconds, shotID: shot.id)
                dialogue.provenance = Provenance(toolID: "voice", cost: 0, prompt: nil)
                try? timeline.append(dialogue, to: "A1")
            }
        }

        if breakdown.workload.musicMinutes > 0 {
            var score = Clip(name: "Score", start: 0, duration: breakdown.workload.musicMinutes * 60)
            score.provenance = Provenance(toolID: "music", cost: 0, prompt: nil)
            try? timeline.append(score, to: "A2")
        }

        for scene in 1...max(1, breakdown.sceneCount) {
            let prefix = String(format: "S%03d", scene)
            if let first = timeline.tracks.first(where: { $0.id == "V1" })?.clips.first(where: { ($0.shotID ?? "").hasPrefix(prefix) }) {
                timeline.addMarker(at: first.start, name: "Scene \(scene)")
            }
        }
        return timeline
    }
}
