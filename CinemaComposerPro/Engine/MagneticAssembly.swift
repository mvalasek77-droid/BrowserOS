import Foundation

extension MagneticTimeline {

    /// Seed a first cut straight from the breakdown, laid out the way Final Cut
    /// would have you build it: picture in the primary storyline, dialogue
    /// connected beneath each shot it belongs to, score connected on its own
    /// lane, and a chapter marker at the head of every scene.
    ///
    /// Dialogue is *connected to its shot* rather than dropped on a track, which
    /// is the whole point of the magnetic model — ripple a shot out of the cut
    /// and its sound leaves with it instead of sliding out of sync.
    static func assembly(from breakdown: Breakdown, plan: ProductionPlan) -> MagneticTimeline {
        let spec = breakdown.spec
        let rate = FrameRate.nearest(to: spec.fps)
        var timeline = MagneticTimeline(
            name: "\(spec.title) — Assembly",
            format: TimelineFormat(rate: rate, resolution: spec.tier.resolution)
        )

        let finals = plan.tasks(in: .photography).filter { !$0.isExplorationPass }
        let photographyCost = plan.tasks(in: .photography).reduce(0) { $0 + $1.cost }
        let perSecond = breakdown.runtimeSeconds <= 0 ? 0 : photographyCost / breakdown.runtimeSeconds
        let heroTool = finals.first { $0.id.contains("hero") }?.toolID ?? finals.first?.toolID ?? "unassigned"
        let bodyTool = finals.first { $0.id.contains("body") }?.toolID ?? heroTool

        var sceneHeads: [Int: String] = [:]

        for shot in breakdown.shots {
            let toolID = shot.needsHeroGenerator ? heroTool : bodyTool
            let cost = shot.seconds * perSecond
            let prompt = "\(spec.style) — scene \(shot.scene)"
            let duration = RationalTime(seconds: shot.seconds, rate: rate)
            guard !duration.isZero else { continue }

            // Source length is unknown until the shot is actually generated, so
            // it stays zero — which this engine reads as "unbounded", leaving
            // roll and slide room to work before the conductor has run.
            let media = MediaRef(assetID: shot.id,
                                 name: shot.id,
                                 sourceDuration: .zero,
                                 hasVideo: true,
                                 hasAudio: false)

            var item = TimelineItem(name: shot.id, content: .media(media), duration: duration, role: .video)
            item.provenance = Provenance(takeID: nil, toolID: toolID, cost: cost, prompt: prompt)
            let take = Take(toolID: toolID, cost: cost, prompt: prompt)
            item.audition = Audition(alternatives: [take], selectedID: take.id)
            item.provenance.takeID = take.id

            if shot.hasDialogue {
                let voiceMedia = MediaRef(assetID: "\(shot.id)-dx",
                                          name: "\(shot.id) DX",
                                          sourceDuration: .zero,
                                          hasVideo: false,
                                          hasAudio: true)
                var dialogue = TimelineItem(name: "\(shot.id) DX",
                                            content: .media(voiceMedia),
                                            duration: duration,
                                            role: .dialogue)
                dialogue.lane = -1
                dialogue.offset = .zero
                dialogue.provenance = Provenance(toolID: "voice", cost: 0, prompt: nil)
                item.connected.append(dialogue)
            }

            if sceneHeads[shot.scene] == nil { sceneHeads[shot.scene] = item.id }
            try? timeline.append(item)
        }

        // Score rides its own lane, anchored to the first shot so it travels
        // with the head of the picture.
        if breakdown.workload.musicMinutes > 0, !timeline.spine.isEmpty {
            let scoreDuration = RationalTime(seconds: breakdown.workload.musicMinutes * 60, rate: rate)
            let scoreMedia = MediaRef(assetID: "score",
                                      name: "Score",
                                      sourceDuration: .zero,
                                      hasVideo: false,
                                      hasAudio: true)
            var score = TimelineItem(name: "Score",
                                     content: .media(scoreMedia),
                                     duration: scoreDuration,
                                     role: .music)
            score.lane = -2
            score.offset = .zero
            score.audio.volumeDB = AnimatableValue(-12)
            score.audio.fadeIn = Fade(duration: RationalTime(seconds: 2, rate: rate), shape: .easeIn)
            score.audio.fadeOut = Fade(duration: RationalTime(seconds: 3, rate: rate), shape: .easeOut)
            score.provenance = Provenance(toolID: "music", cost: 0, prompt: nil)
            timeline.spine[0].connected.append(score)
        }

        for (scene, itemID) in sceneHeads.sorted(by: { $0.key < $1.key }) {
            let marker = EditMarker(at: .zero, name: "Scene \(scene)", kind: .chapter)
            try? timeline.addMarker(marker, to: itemID)
        }

        timeline.snapToFrames()
        return timeline
    }

    /// Import a track-model sequence into the magnetic one. The first video
    /// track becomes the primary storyline — with real gaps where it had holes,
    /// since a magnetic storyline has no empty space — and every other track's
    /// clips are connected to whichever storyline clip is under them.
    ///
    /// This is how a project saved before the magnetic engine, or a demo cut
    /// built against the old model, opens in the new cutting room.
    init(importing flat: Timeline) {
        let frameRate = FrameRate.nearest(to: flat.fps)
        self.init(name: flat.name, format: TimelineFormat(rate: frameRate,
                                                          resolution: flat.resolution))

        func convert(_ clip: Clip, role: Role) -> TimelineItem {
            let media = MediaRef(assetID: clip.shotID ?? clip.id,
                                 name: clip.name,
                                 sourceDuration: .zero,
                                 hasVideo: role.kind != .audio,
                                 hasAudio: role.kind == .audio)
            var item = TimelineItem(name: clip.name,
                                    content: .media(media),
                                    duration: RationalTime(seconds: clip.duration, rate: frameRate),
                                    sourceIn: RationalTime(seconds: clip.sourceIn, rate: frameRate),
                                    role: role)
            item.isEnabled = clip.isEnabled
            item.isLocked = clip.isLocked
            item.provenance = clip.provenance
            if !clip.takes.isEmpty {
                item.audition = Audition(alternatives: clip.takes,
                                         selectedID: clip.provenance.takeID ?? clip.takes.first?.id)
            }
            if let transition = clip.transitionIn {
                item.transitionIn = EditTransition(
                    name: transition.type.capitalized,
                    duration: RationalTime(seconds: transition.duration, rate: frameRate))
            }
            return item
        }

        // Storyline from the first video track, gaps filling any holes.
        if let video = flat.tracks.first(where: { $0.kind == .video }) {
            var cursor = RationalTime.zero
            for clip in video.clips.sorted(by: { $0.start < $1.start }) {
                let start = RationalTime(seconds: clip.start, rate: frameRate)
                if cursor < start {
                    spine.append(TimelineItem.gap(duration: start - cursor))
                    cursor = start
                }
                let item = convert(clip, role: .video)
                guard !item.duration.isZero else { continue }
                spine.append(item)
                cursor += item.duration
            }
        }
        if spine.isEmpty, !flat.allClips.isEmpty {
            // Audio-only source still needs something to anchor to.
            let span = RationalTime(seconds: flat.duration, rate: frameRate)
            if !span.isZero { spine.append(TimelineItem.gap(duration: span)) }
        }

        // Everything else hangs off the storyline clip beneath it.
        var lane = -1
        for track in flat.tracks where track.kind == .audio {
            let role: Role = lane == -1 ? .dialogue : .music
            for clip in track.clips.sorted(by: { $0.start < $1.start }) {
                let start = RationalTime(seconds: clip.start, rate: frameRate)
                guard let anchor = storylineItem(at: start) else { continue }
                var item = convert(clip, role: role)
                guard !item.duration.isZero else { continue }
                item.lane = lane
                item.offset = start - anchor.start
                spine[anchor.index].connected.append(item)
            }
            lane -= 1
        }

        for marker in flat.markers {
            markers.append(EditMarker(at: RationalTime(seconds: marker.at, rate: frameRate),
                                      name: marker.name,
                                      note: marker.note))
        }
        snapToFrames()
    }

    /// Bridge to the original track model so the existing EDL/OTIO exporters and
    /// the budget's cost-of-cut keep working while the new engine takes over.
    /// The storyline becomes V1; connected lanes flatten to A1, A2… by role.
    func flattenedToTrackModel() -> Timeline {
        var flat = Timeline(name: name, fps: 1.0 / format.rate.frameDuration.seconds,
                            resolution: format.resolution)
        flat.tracks = [Track(id: "V1", kind: .video)]

        var audioTrackForLane: [Int: String] = [:]
        for placed in placedItems.sorted(by: { $0.start < $1.start }) {
            let item = placed.item
            guard !item.content.isGap else { continue }

            var clip = Clip(name: item.name,
                            start: placed.start.seconds,
                            duration: item.duration.seconds,
                            shotID: item.content.mediaRef?.assetID)
            clip.sourceIn = item.sourceIn.seconds
            clip.sourceOut = item.sourceOut.seconds
            clip.isEnabled = item.isEnabled
            clip.isLocked = item.isLocked
            clip.provenance = item.provenance
            clip.takes = item.audition?.alternatives ?? []
            if let transition = item.transitionIn {
                clip.transitionIn = Transition(type: transition.name, duration: transition.duration.seconds)
            }

            if placed.lane >= 0 && item.role.kind != .audio {
                flat.tracks[0].clips.append(clip)
            } else {
                let trackID: String
                if let existing = audioTrackForLane[placed.lane] {
                    trackID = existing
                } else {
                    trackID = flat.addTrack(kind: .audio)
                    audioTrackForLane[placed.lane] = trackID
                }
                if let index = flat.tracks.firstIndex(where: { $0.id == trackID }) {
                    flat.tracks[index].clips.append(clip)
                }
            }
        }

        for entry in allMarkers {
            flat.addMarker(at: entry.at.seconds, name: entry.marker.name, note: entry.marker.note)
        }
        return flat
    }
}
