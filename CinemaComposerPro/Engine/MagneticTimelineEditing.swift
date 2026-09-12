import Foundation

/// Which end of a clip an edit grabs.
enum EditEdge: String, Codable, CaseIterable {
    case head, tail

    var label: String { self == .head ? "Head" : "Tail" }
}

extension MagneticTimeline {

    // MARK: - Bounds

    /// How much media sits behind the head — the room a slip or head-trim has to
    /// move into. Generated media with an unknown source length is treated as
    /// unbounded, which is the honest answer before the conductor has run.
    func availableHead(of item: TimelineItem) -> RationalTime? {
        item.sourceIn
    }

    func availableTail(of item: TimelineItem) -> RationalTime? {
        guard let ref = item.content.mediaRef, !ref.sourceDuration.isZero else { return nil }
        return ref.sourceDuration - item.sourceOut
    }

    private func requireSpineIndex(_ itemID: String) throws -> Int {
        guard let index = spineIndex(of: itemID) else {
            if path(to: itemID) != nil { throw MagneticEditError.notInStoryline(itemID) }
            throw MagneticEditError.noSuchItem(itemID)
        }
        return index
    }

    private func assertUnlocked(_ item: TimelineItem) throws {
        if item.isLocked { throw MagneticEditError.itemLocked(item.name) }
    }

    // MARK: - Assembly edits

    /// Put it at the end of the storyline. The fastest way to build an assembly.
    @discardableResult
    mutating func append(_ item: TimelineItem) throws -> TimelineItem {
        guard !item.duration.isZero, !item.duration.isNegative else {
            throw MagneticEditError.nonPositiveDuration
        }
        var placed = item
        placed.lane = 0
        placed.offset = .zero
        placed.duration = placed.duration.snapped(to: rate)
        spine.append(placed)
        return placed
    }

    /// Insert at a point, pushing everything downstream later — Final Cut's W.
    /// Landing mid-clip blades it first, which is exactly what the app does.
    @discardableResult
    mutating func insert(_ item: TimelineItem, at time: RationalTime) throws -> TimelineItem {
        guard !item.duration.isZero, !item.duration.isNegative else {
            throw MagneticEditError.nonPositiveDuration
        }
        let snapped = time.snapped(to: rate)
        var placed = item
        placed.lane = 0
        placed.offset = .zero
        placed.duration = placed.duration.snapped(to: rate)

        guard let target = storylineItem(at: snapped) else {
            spine.append(placed)
            return placed
        }
        if target.start < snapped, snapped < target.start + target.item.duration {
            try blade(target.item.id, at: snapped, bladeConnected: false)
        }
        // After a blade the boundary exists; find the index that now starts here.
        var cursor = RationalTime.zero
        var insertAt = spine.count
        for (index, existing) in spine.enumerated() {
            if snapped <= cursor { insertAt = index; break }
            cursor += existing.duration
        }
        spine.insert(placed, at: insertAt)
        return placed
    }

    /// Drop on top, replacing whatever occupies that range. Nothing downstream
    /// moves — Final Cut's D.
    @discardableResult
    mutating func overwrite(_ item: TimelineItem, at time: RationalTime) throws -> TimelineItem {
        guard !item.duration.isZero, !item.duration.isNegative else {
            throw MagneticEditError.nonPositiveDuration
        }
        var placed = item
        placed.lane = 0
        placed.offset = .zero
        placed.duration = placed.duration.snapped(to: rate)

        let start = time.snapped(to: rate)
        let end = start + placed.duration

        // If it lands past the end, pad with a gap so timing still reads true.
        if duration <= start {
            let padding = start - duration
            if !padding.isZero, !padding.isNegative {
                spine.append(TimelineItem.gap(duration: padding))
            }
            spine.append(placed)
            return placed
        }

        // Cut clean edges, then swap out everything strictly inside.
        if let head = storylineItem(at: start), head.start < start,
           start < head.start + head.item.duration {
            try blade(head.item.id, at: start, bladeConnected: false)
        }
        if end < duration, let tail = storylineItem(at: end), tail.start < end,
           end < tail.start + tail.item.duration {
            try blade(tail.item.id, at: end, bladeConnected: false)
        }

        var cursor = RationalTime.zero
        var firstIndex: Int?
        var lastIndex: Int?
        for (index, existing) in spine.enumerated() {
            let itemEnd = cursor + existing.duration
            if start <= cursor, itemEnd <= end {
                if firstIndex == nil { firstIndex = index }
                lastIndex = index
            }
            cursor = itemEnd
        }

        guard let first = firstIndex, let last = lastIndex else {
            spine.append(placed)
            return placed
        }
        // Anything hanging off the replaced clips is replaced along with them.
        spine.replaceSubrange(first...last, with: [placed])

        // The incoming clip may be shorter than what it displaced; hold the
        // remaining time with a gap so downstream timing is untouched.
        let replacedSpan = end - start
        if placed.duration < replacedSpan {
            let remainder = replacedSpan - placed.duration
            spine.insert(TimelineItem.gap(duration: remainder), at: first + 1)
        }
        return placed
    }

    /// Attach a clip to whatever the storyline is showing at that moment, on a
    /// lane above or below — Final Cut's Q. This is how titles, cutaways, score
    /// and sound effects live in a magnetic timeline.
    @discardableResult
    mutating func connect(_ item: TimelineItem,
                          at time: RationalTime,
                          lane: Int) throws -> TimelineItem {
        guard lane != 0 else { throw MagneticEditError.laneZeroReserved }
        guard !item.duration.isZero, !item.duration.isNegative else {
            throw MagneticEditError.nonPositiveDuration
        }
        let snapped = time.snapped(to: rate)
        guard let anchor = storylineItem(at: snapped) else {
            // Nothing to anchor to yet — seed the storyline with a gap so the
            // connected clip still has a home.
            let gap = TimelineItem.gap(duration: snapped + item.duration)
            spine.append(gap)
            var child = item
            child.lane = lane
            child.offset = snapped
            spine[spine.count - 1].connected.append(child)
            return child
        }
        var child = item
        child.lane = lane
        child.offset = (snapped - anchor.start).snapped(to: rate)
        child.duration = child.duration.snapped(to: rate)
        spine[anchor.index].connected.append(child)
        return child
    }

    /// Swap an item's media while keeping its slot, length and lane — the edit
    /// behind "use this take instead".
    mutating func replace(_ itemID: String, with content: ItemContent, name: String) throws {
        try update(id: itemID) { item in
            item.content = content
            item.name = name
        }
    }

    // MARK: - Blade

    /// Cut at a point. `bladeConnected` is Final Cut's Blade All: it carries the
    /// cut up and down every lane anchored to the same storyline clip.
    @discardableResult
    mutating func blade(_ itemID: String,
                        at time: RationalTime,
                        bladeConnected: Bool = false) throws -> [String] {
        let index = try requireSpineIndex(itemID)
        let item = spine[index]
        try assertUnlocked(item)

        let start = spineStart(at: index)
        let cut = time.snapped(to: rate)
        let offset = cut - start
        guard !offset.isZero, !offset.isNegative, offset < item.duration else {
            throw MagneticEditError.bladeOutsideItem
        }

        var head = item
        var tail = item
        tail.id = UUID().uuidString

        head.duration = offset
        head.transitionOut = nil

        tail.duration = item.duration - offset
        tail.sourceIn = item.sourceIn + offset
        tail.transitionIn = nil
        tail.shiftAllKeyframes(by: -offset)

        // Markers and connected clips follow the half they actually sit on.
        head.markers = item.markers.filter { $0.at < offset }
        tail.markers = item.markers.filter { offset <= $0.at }.map { marker in
            var moved = marker
            moved.at = marker.at - offset
            return moved
        }

        head.connected = []
        tail.connected = []
        for child in item.connected {
            if child.offset < offset {
                head.connected.append(child)
            } else {
                var moved = child
                moved.offset = child.offset - offset
                tail.connected.append(moved)
            }
        }

        // Fades belong to the outer edges of the original clip.
        head.audio.fadeOut = Fade()
        tail.audio.fadeIn = Fade()

        spine.replaceSubrange(index...index, with: [head, tail])

        if bladeConnected {
            bladeConnectedClips(ofSpineIndex: index, at: cut)
        }
        return [head.id, tail.id]
    }

    /// Carry a cut through every connected clip that straddles it.
    private mutating func bladeConnectedClips(ofSpineIndex index: Int, at cut: RationalTime) {
        let headStart = spineStart(at: index)
        var splitHead: [TimelineItem] = []
        for child in spine[index].connected {
            let childStart = headStart + child.offset
            let childEnd = childStart + child.duration
            guard childStart < cut, cut < childEnd else {
                splitHead.append(child)
                continue
            }
            let offset = cut - childStart
            var a = child
            var b = child
            b.id = UUID().uuidString
            a.duration = offset
            b.duration = child.duration - offset
            b.sourceIn = child.sourceIn + offset
            b.offset = child.offset + offset
            b.shiftAllKeyframes(by: -offset)
            a.audio.fadeOut = Fade()
            b.audio.fadeIn = Fade()
            splitHead.append(a)
            splitHead.append(b)
        }
        spine[index].connected = splitHead
    }

    /// Cut every clip the playhead touches, storyline and lanes alike.
    @discardableResult
    mutating func bladeAll(at time: RationalTime) throws -> [String] {
        guard let target = storylineItem(at: time) else { return [] }
        let cut = time.snapped(to: rate)
        guard target.start < cut, cut < target.start + target.item.duration else { return [] }
        return try blade(target.item.id, at: cut, bladeConnected: true)
    }

    // MARK: - Removing

    /// Remove and close the gap. Connected clips go with their anchor, which is
    /// the behaviour that keeps sound attached to picture.
    @discardableResult
    mutating func rippleDelete(_ itemID: String) throws -> TimelineItem {
        if let index = spineIndex(of: itemID) {
            try assertUnlocked(spine[index])
            return spine.remove(at: index)
        }
        return try detach(itemID)
    }

    /// Remove but hold the time — the clip becomes a gap. Final Cut's
    /// Replace with Gap, and the reason "delete" never desyncs a cut.
    @discardableResult
    mutating func lift(_ itemID: String) throws -> TimelineItem {
        let index = try requireSpineIndex(itemID)
        try assertUnlocked(spine[index])
        let removed = spine[index]
        spine[index] = TimelineItem.gap(duration: removed.duration)
        return removed
    }

    /// Collapse consecutive gaps and drop zero-length debris.
    mutating func tidy() {
        var cleaned: [TimelineItem] = []
        for item in spine {
            if item.duration.isZero || item.duration.isNegative { continue }
            if item.content.isGap, item.connected.isEmpty,
               let last = cleaned.last, last.content.isGap, last.connected.isEmpty {
                cleaned[cleaned.count - 1].duration += item.duration
                continue
            }
            cleaned.append(item)
        }
        while let last = cleaned.last, last.content.isGap, last.connected.isEmpty {
            cleaned.removeLast()
        }
        spine = cleaned
    }

    // MARK: - The four trims

    /// Ripple: move one edge and let everything downstream slide. Length of the
    /// sequence changes; the cut either side of it does not move relative to
    /// its own media.
    @discardableResult
    mutating func rippleTrim(_ itemID: String,
                             edge: EditEdge,
                             by delta: RationalTime) throws -> TimelineItem {
        guard let itemPath = path(to: itemID) else { throw MagneticEditError.noSuchItem(itemID) }
        guard let current = item(at: itemPath) else { throw MagneticEditError.noSuchItem(itemID) }
        try assertUnlocked(current)

        let step = delta.snapped(to: rate)
        var result = current
        switch edge {
        case .head:
            // Positive delta trims media off the head.
            let newDuration = current.duration - step
            guard !newDuration.isZero, !newDuration.isNegative else {
                throw MagneticEditError.trimConsumesItem
            }
            if step.isNegative, let room = availableHead(of: current), room < -step {
                throw MagneticEditError.noRoomToTrim
            }
            result.sourceIn = current.sourceIn + step
            result.duration = newDuration
            result.shiftAllKeyframes(by: -step)
            result.markers = current.markers.compactMap { marker -> EditMarker? in
                var moved = marker
                moved.at = marker.at - step
                if moved.at.isNegative { return nil }
                return moved
            }
            // A connected clip's offset is measured from its anchor's start, so
            // trimming the anchor's head must not drag the attachments.
            result.connected = current.connected.map { child in
                var moved = child
                moved.offset = child.offset - step
                return moved
            }
        case .tail:
            let newDuration = current.duration - step
            guard !newDuration.isZero, !newDuration.isNegative else {
                throw MagneticEditError.trimConsumesItem
            }
            if step.isNegative, let room = availableTail(of: current), room < -step {
                throw MagneticEditError.noRoomToTrim
            }
            result.duration = newDuration
        }
        try update(at: itemPath) { $0 = result }
        return result
    }

    /// Roll: move the edit point between two neighbours. Both clips change, the
    /// sequence length does not — the classic two-up trim.
    mutating func roll(betweenItem leftID: String, by delta: RationalTime) throws {
        let index = try requireSpineIndex(leftID)
        guard index + 1 < spine.count else { throw MagneticEditError.noRoomToTrim }
        try assertUnlocked(spine[index])
        try assertUnlocked(spine[index + 1])

        let step = delta.snapped(to: rate)
        let left = spine[index]
        let right = spine[index + 1]

        let newLeft = left.duration + step
        let newRight = right.duration - step
        guard !newLeft.isZero, !newLeft.isNegative else { throw MagneticEditError.trimConsumesItem }
        guard !newRight.isZero, !newRight.isNegative else { throw MagneticEditError.trimConsumesItem }
        if step.isNegative, let room = availableHead(of: right), room < -step {
            throw MagneticEditError.noRoomToTrim
        }
        if !step.isNegative, let room = availableTail(of: left), room < step {
            throw MagneticEditError.noRoomToTrim
        }

        spine[index].duration = newLeft
        spine[index + 1].duration = newRight
        spine[index + 1].sourceIn = right.sourceIn + step
        spine[index + 1].shiftAllKeyframes(by: -step)
    }

    /// Slip: change which piece of the source plays without moving the clip or
    /// changing its length. Nothing else in the sequence notices.
    @discardableResult
    mutating func slip(_ itemID: String, by delta: RationalTime) throws -> TimelineItem {
        guard let itemPath = path(to: itemID) else { throw MagneticEditError.noSuchItem(itemID) }
        guard let current = item(at: itemPath) else { throw MagneticEditError.noSuchItem(itemID) }
        try assertUnlocked(current)

        let step = delta.snapped(to: rate)
        var newIn = current.sourceIn + step
        if newIn.isNegative { newIn = .zero }
        if let ref = current.content.mediaRef, !ref.sourceDuration.isZero {
            let latest = ref.sourceDuration - current.sourceUsed
            if latest < newIn { newIn = RationalTime.max(.zero, latest) }
        }
        var result = current
        result.sourceIn = newIn
        try update(at: itemPath) { $0 = result }
        return result
    }

    /// Slide: move a clip along the timeline while its neighbours absorb the
    /// difference. The clip's own media is untouched; the cuts either side move.
    mutating func slide(_ itemID: String, by delta: RationalTime) throws {
        let index = try requireSpineIndex(itemID)
        guard index > 0, index + 1 < spine.count else { throw MagneticEditError.noRoomToTrim }
        try assertUnlocked(spine[index])

        let step = delta.snapped(to: rate)
        let before = spine[index - 1]
        let after = spine[index + 1]

        let newBefore = before.duration + step
        let newAfter = after.duration - step
        guard !newBefore.isZero, !newBefore.isNegative else { throw MagneticEditError.trimConsumesItem }
        guard !newAfter.isZero, !newAfter.isNegative else { throw MagneticEditError.trimConsumesItem }
        if !step.isNegative, let room = availableTail(of: before), room < step {
            throw MagneticEditError.noRoomToTrim
        }
        if step.isNegative, let room = availableHead(of: after), room < -step {
            throw MagneticEditError.noRoomToTrim
        }

        spine[index - 1].duration = newBefore
        spine[index + 1].duration = newAfter
        spine[index + 1].sourceIn = after.sourceIn + step
        spine[index + 1].shiftAllKeyframes(by: -step)
    }

    // MARK: - Compound clips

    /// Wrap a contiguous run of the storyline into one clip you can edit inside.
    @discardableResult
    mutating func makeCompound(from itemIDs: [String], name: String) throws -> TimelineItem {
        let indices = itemIDs.compactMap { spineIndex(of: $0) }.sorted()
        guard let first = indices.first, let last = indices.last,
              !indices.isEmpty, last - first == indices.count - 1 else {
            throw MagneticEditError.cannotNestSelection
        }
        let nested = Array(spine[first...last])
        let total = nested.reduce(RationalTime.zero) { $0 + $1.duration }
        var compound = TimelineItem(name: name,
                                    content: .compound(items: nested),
                                    duration: total)
        compound.role = nested.first?.role ?? .video
        spine.replaceSubrange(first...last, with: [compound])
        return compound
    }

    /// Dissolve a compound back into the storyline it came from.
    mutating func breakApart(_ itemID: String) throws {
        let index = try requireSpineIndex(itemID)
        guard case .compound(let items) = spine[index].content else { return }
        let carried = spine[index].connected
        var restored = items
        if !carried.isEmpty, !restored.isEmpty {
            restored[0].connected.append(contentsOf: carried)
        }
        spine.replaceSubrange(index...index, with: restored)
    }

    // MARK: - Retiming

    /// Set a constant speed. The clip's timeline length changes and, because the
    /// storyline is magnetic, everything after it moves to suit.
    mutating func setSpeed(_ itemID: String, percent: Double) throws {
        guard percent > 0 else { throw MagneticEditError.nonPositiveDuration }
        // Bound the frame rate into a local first: reading `self.rate` inside a
        // closure that `update` is already mutating `self` through would be an
        // overlapping access.
        let frameRate = rate
        try update(id: itemID) { item in
            let source = item.sourceUsed
            let rateValue = RationalTime(Int64((percent * 1000).rounded()), 100_000)
            item.retime = Retime.constant(rate: rateValue, sourceDuration: source)
            item.duration = (source / rateValue).snapped(to: frameRate)
        }
    }

    /// A speed ramp between two rates across the clip.
    mutating func setSpeedRamp(_ itemID: String, fromPercent: Double, toPercent: Double) throws {
        guard fromPercent > 0, toPercent > 0 else { throw MagneticEditError.nonPositiveDuration }
        let frameRate = rate
        try update(id: itemID) { item in
            let source = item.sourceUsed
            let start = RationalTime(Int64((fromPercent * 1000).rounded()), 100_000)
            let end = RationalTime(Int64((toPercent * 1000).rounded()), 100_000)
            let segment = RetimeSegment(kind: .ramp, sourceStart: .zero, sourceEnd: source,
                                        rate: start, endRate: end)
            item.retime = Retime(segments: [segment])
            item.duration = segment.timelineDuration.snapped(to: frameRate)
        }
    }

    mutating func clearRetime(_ itemID: String) throws {
        try update(id: itemID) { item in
            let source = item.sourceUsed
            item.retime = nil
            item.duration = source
        }
    }

    // MARK: - Auditions, markers, keywords

    mutating func addTake(_ take: Take, to itemID: String, select: Bool = true) throws {
        try update(id: itemID) { item in
            var audition = item.audition ?? Audition()
            audition.alternatives.append(take)
            if select || audition.selectedID == nil { audition.selectedID = take.id }
            item.audition = audition
            if select {
                item.provenance = Provenance(takeID: take.id, toolID: take.toolID,
                                             cost: take.cost, prompt: take.prompt)
            }
        }
    }

    mutating func selectTake(_ takeID: String, on itemID: String) throws {
        guard let existing = item(itemID) else { throw MagneticEditError.noSuchItem(itemID) }
        guard let take = existing.audition?.alternatives.first(where: { $0.id == takeID }) else {
            throw MagneticEditError.noSuchItem(takeID)
        }
        try update(id: itemID) { item in
            item.audition?.selectedID = takeID
            item.provenance = Provenance(takeID: take.id, toolID: take.toolID,
                                         cost: take.cost, prompt: take.prompt)
        }
    }

    mutating func addMarker(_ marker: EditMarker, to itemID: String) throws {
        try update(id: itemID) { item in
            item.markers.append(marker)
            item.markers.sort { $0.at < $1.at }
        }
    }

    mutating func setRating(_ rating: Rating?, on itemID: String) throws {
        try update(id: itemID) { $0.rating = rating }
    }

    mutating func addKeyword(_ name: String, to itemID: String) throws {
        try update(id: itemID) { item in
            let keyword = Keyword(name: name, start: .zero, duration: item.duration)
            item.keywords.append(keyword)
        }
    }

    mutating func setRole(_ role: Role, on itemID: String) throws {
        try update(id: itemID) { $0.role = role }
    }

    mutating func setEnabled(_ enabled: Bool, on itemID: String) throws {
        try update(id: itemID) { $0.isEnabled = enabled }
    }

    mutating func setLocked(_ locked: Bool, on itemID: String) throws {
        try update(id: itemID) { $0.isLocked = locked }
    }

    // MARK: - Transitions and fades

    /// Final Cut needs handles either side of a cut to build a transition; a
    /// centered dissolve eats half its duration from each neighbour.
    mutating func addTransition(_ transition: EditTransition, to itemID: String, edge: EditEdge) throws {
        try update(id: itemID) { item in
            switch edge {
            case .head: item.transitionIn = transition
            case .tail: item.transitionOut = transition
            }
        }
    }

    mutating func removeTransition(from itemID: String, edge: EditEdge) throws {
        try update(id: itemID) { item in
            switch edge {
            case .head: item.transitionIn = nil
            case .tail: item.transitionOut = nil
            }
        }
    }

    mutating func setFade(_ fade: Fade, on itemID: String, edge: EditEdge) throws {
        try update(id: itemID) { item in
            switch edge {
            case .head: item.audio.fadeIn = fade
            case .tail: item.audio.fadeOut = fade
            }
        }
    }

    // MARK: - Split edits

    /// A J- or L-cut: detach this clip's audio onto its own lane so sound can
    /// lead or trail the picture. `lead` positive pulls the audio earlier.
    @discardableResult
    mutating func detachAudio(from itemID: String, lead: RationalTime = .zero) throws -> TimelineItem {
        let index = try requireSpineIndex(itemID)
        let parent = spine[index]
        try assertUnlocked(parent)

        var audio = parent
        audio.id = UUID().uuidString
        audio.name = "\(parent.name) · Audio"
        audio.role = parent.role.kind == .audio ? parent.role : .dialogue
        audio.lane = -1
        audio.offset = (RationalTime.zero - lead).snapped(to: rate)
        audio.connected = []
        audio.transform = Transform()
        audio.provenance = Provenance()
        audio.audition = nil

        spine[index].connected.append(audio)
        return audio
    }
}
