import Foundation

/// The professional edit surface: effects stacks, grading, adjustment layers,
/// captions, multicam and role operations — plus the blade and transition
/// behaviours that a working editor expects and the basic engine left strict.
extension MagneticTimeline {

    // MARK: - Effects

    mutating func addEffect(_ effect: Effect, to itemID: String) throws {
        var fresh = effect
        fresh.id = UUID().uuidString
        try update(id: itemID) { $0.effects.append(fresh) }
    }

    mutating func removeEffect(_ effectID: String, from itemID: String) throws {
        try update(id: itemID) { $0.effects.removeAll { $0.id == effectID } }
    }

    mutating func setEffectEnabled(_ enabled: Bool, effectID: String, on itemID: String) throws {
        try update(id: itemID) { item in
            guard let index = item.effects.firstIndex(where: { $0.id == effectID }) else { return }
            item.effects[index].isEnabled = enabled
        }
    }

    /// Order is meaning: a blur above a grade blurs the graded picture.
    mutating func moveEffect(_ effectID: String, on itemID: String, to destination: Int) throws {
        try update(id: itemID) { item in
            guard let index = item.effects.firstIndex(where: { $0.id == effectID }) else { return }
            let effect = item.effects.remove(at: index)
            let clamped = Swift.min(Swift.max(destination, 0), item.effects.count)
            item.effects.insert(effect, at: clamped)
        }
    }

    mutating func setEffectParameter(_ value: Double,
                                     parameterID: String,
                                     effectID: String,
                                     on itemID: String) throws {
        try update(id: itemID) { item in
            guard let index = item.effects.firstIndex(where: { $0.id == effectID }) else { return }
            item.effects[index].setParameter(parameterID, to: value)
        }
    }

    /// Copy one clip's whole look onto others — the paste-attributes an editor
    /// reaches for after grading the first shot of a scene.
    mutating func pasteAttributes(from sourceID: String,
                                  to targetIDs: [String],
                                  includeEffects: Bool = true,
                                  includeColor: Bool = true,
                                  includeTransform: Bool = false,
                                  includeAudio: Bool = false) throws {
        guard let source = item(sourceID) else { throw MagneticEditError.noSuchItem(sourceID) }
        for targetID in targetIDs where targetID != sourceID {
            try? update(id: targetID) { item in
                if includeEffects {
                    item.effects = source.effects.map { effect in
                        var copy = effect
                        copy.id = UUID().uuidString
                        return copy
                    }
                }
                if includeColor { item.color = source.color }
                if includeTransform { item.transform = source.transform }
                if includeAudio {
                    item.audio = source.audio
                    item.audioProcessing = source.audioProcessing
                }
            }
        }
    }

    // MARK: - Colour

    mutating func setColor(_ color: ColorCorrection, on itemID: String) throws {
        try update(id: itemID) { $0.color = color }
    }

    mutating func resetColor(on itemID: String) throws {
        try update(id: itemID) { $0.color = ColorCorrection() }
    }

    // MARK: - Adjustment layers

    /// Drop an adjustment layer across a span. Everything on lower lanes beneath
    /// it inherits its grade and effects, so a whole scene can be tuned at once.
    /// Final Cut has no native equivalent — it makes you build a Motion template.
    @discardableResult
    mutating func addAdjustmentLayer(named name: String,
                                     start: RationalTime,
                                     duration: RationalTime,
                                     lane: Int = 2) throws -> TimelineItem {
        guard !duration.isZero, !duration.isNegative else {
            throw MagneticEditError.nonPositiveDuration
        }
        var layer = TimelineItem(name: name, content: .gap, duration: duration, role: .video)
        layer.isAdjustmentLayer = true
        return try connect(layer, at: start, lane: lane)
    }

    /// Every clip an adjustment layer covers: lower lanes, overlapping in time.
    func itemsAffected(byAdjustmentLayer layerID: String) -> [PlacedItem] {
        guard let layer = placed(layerID), layer.item.isAdjustmentLayer else { return [] }
        return placedItems.filter { candidate in
            guard candidate.item.id != layerID else { return false }
            guard candidate.lane < layer.lane else { return false }
            return candidate.start < layer.end && layer.start < candidate.end
        }
    }

    /// The grade actually seen on a clip: its own, plus every adjustment layer
    /// stacked above it, applied bottom up.
    func effectiveEffects(for itemID: String) -> [Effect] {
        guard let target = placed(itemID) else { return [] }
        var stack = target.item.effects
        let layers = placedItems
            .filter { $0.item.isAdjustmentLayer && $0.lane > target.lane }
            .filter { $0.start < target.end && target.start < $0.end }
            .sorted { $0.lane < $1.lane }
        for layer in layers { stack.append(contentsOf: layer.item.effects) }
        return stack
    }

    // MARK: - Captions

    @discardableResult
    mutating func addCaption(_ text: String,
                             at start: RationalTime,
                             duration: RationalTime,
                             language: String = "en",
                             lane: Int = 3) throws -> TimelineItem {
        guard !duration.isZero, !duration.isNegative else {
            throw MagneticEditError.nonPositiveDuration
        }
        let content = CaptionContent(text: text, language: language)
        var item = TimelineItem(name: text.isEmpty ? "Caption" : text,
                                content: .caption(content),
                                duration: duration,
                                role: Role(name: "Captions", kind: .title))
        item.lane = lane
        return try connect(item, at: start, lane: lane)
    }

    mutating func setCaptionText(_ text: String, on itemID: String) throws {
        try update(id: itemID) { item in
            guard case .caption(var caption) = item.content else { return }
            caption.text = text
            item.content = .caption(caption)
            item.name = text.isEmpty ? "Caption" : text
        }
    }

    /// Captions that break the readability rules a broadcaster will check.
    func captionWarnings() -> [(item: PlacedItem, warning: String)] {
        placedItems.compactMap { placed in
            guard case .caption(let caption) = placed.item.content else { return nil }
            guard let warning = caption.readingRateWarning(duration: placed.item.duration) else { return nil }
            return (placed, warning)
        }
    }

    // MARK: - Multicam

    @discardableResult
    mutating func makeMulticam(from itemIDs: [String], name: String) throws -> TimelineItem {
        let sources = itemIDs.compactMap { item($0) }
        guard sources.count > 1 else { throw MagneticEditError.cannotNestSelection }

        let angles = sources.enumerated().map { index, source in
            MulticamAngle(name: "Angle \(index + 1)", items: [source])
        }
        var content = MulticamContent(angles: angles)
        content.activeVideoAngleID = angles.first?.id
        content.activeAudioAngleID = angles.first?.id

        let duration = content.duration
        var multicam = TimelineItem(name: name, content: .multicam(content), duration: duration)

        // Replace the first source in place; remove the rest.
        guard let firstIndex = spineIndex(of: itemIDs[0]) else {
            throw MagneticEditError.notInStoryline(itemIDs[0])
        }
        multicam.duration = duration.isZero ? spine[firstIndex].duration : duration
        spine[firstIndex] = multicam
        for id in itemIDs.dropFirst() { _ = try? rippleDelete(id) }
        return multicam
    }

    /// Cut to a different angle. The other angles stay in the clip, so the
    /// decision can be revised later without re-conforming anything.
    mutating func switchAngle(on itemID: String, to angleID: String, audioToo: Bool = false) throws {
        guard let existing = item(itemID) else { throw MagneticEditError.noSuchItem(itemID) }
        guard case .multicam(let content) = existing.content else {
            throw MagneticEditError.notMulticam(existing.name)
        }
        guard content.angles.contains(where: { $0.id == angleID }) else {
            throw MagneticEditError.noSuchAngle(angleID)
        }
        try update(id: itemID) { item in
            guard case .multicam(var multicam) = item.content else { return }
            multicam.activeVideoAngleID = angleID
            if audioToo { multicam.activeAudioAngleID = angleID }
            item.content = .multicam(multicam)
        }
    }

    /// Blade a multicam at the playhead and switch the back half — the standard
    /// way a multicam edit is actually made.
    mutating func cutToAngle(on itemID: String, at time: RationalTime, angleID: String) throws {
        let pieces = try blade(itemID, at: time)
        guard let tailID = pieces.last else { return }
        try switchAngle(on: tailID, to: angleID, audioToo: false)
    }

    // MARK: - Blade, anywhere

    /// Blade any clip, connected ones included. The strict engine only cuts the
    /// storyline; an editor expects to cut a connected title or music bed too.
    @discardableResult
    mutating func bladeAnywhere(_ itemID: String, at absoluteTime: RationalTime) throws -> [String] {
        if spineIndex(of: itemID) != nil {
            return try blade(itemID, at: absoluteTime)
        }
        guard let itemPath = path(to: itemID), let target = placed(itemID) else {
            throw MagneticEditError.noSuchItem(itemID)
        }
        try assertEditable(target.item)

        let cut = absoluteTime.snapped(to: rate)
        let offset = cut - target.start
        guard !offset.isZero, !offset.isNegative, offset < target.item.duration else {
            throw MagneticEditError.bladeOutsideItem
        }

        var head = target.item
        var tail = target.item
        tail.id = UUID().uuidString

        head.duration = offset
        head.audio.fadeOut = Fade()
        head.markers = target.item.markers.filter { $0.at < offset }

        tail.duration = target.item.duration - offset
        tail.sourceIn = target.item.sourceIn + offset
        tail.offset = target.item.offset + offset
        tail.audio.fadeIn = Fade()
        tail.shiftAllKeyframes(by: -offset)
        tail.markers = target.item.markers.filter { offset <= $0.at }.map { marker in
            var moved = marker
            moved.at = marker.at - offset
            return moved
        }

        // Both halves live beside each other under the same anchor.
        let parentPath = Array(itemPath.dropLast())
        let childIndex = itemPath[itemPath.count - 1]
        if parentPath.isEmpty {
            guard spine.indices.contains(childIndex) else { throw MagneticEditError.noSuchItem(itemID) }
            spine[childIndex] = head
            spine.insert(tail, at: childIndex + 1)
        } else {
            update(at: parentPath) { parent in
                guard parent.connected.indices.contains(childIndex) else { return }
                parent.connected[childIndex] = head
                parent.connected.insert(tail, at: childIndex + 1)
            }
        }
        return [head.id, tail.id]
    }

    private func assertEditable(_ item: TimelineItem) throws {
        if item.isLocked { throw MagneticEditError.itemLocked(item.name) }
    }

    // MARK: - Transitions with handles

    /// Add a transition only if there is media to build it from.
    ///
    /// A centred dissolve borrows half its length from each side. Final Cut
    /// refuses when the handles are not there rather than silently shortening
    /// the cut, and so does this — the error says which clip is short.
    mutating func addTransitionChecked(_ transition: EditTransition,
                                       to itemID: String,
                                       edge: EditEdge) throws {
        guard let target = item(itemID) else { throw MagneticEditError.noSuchItem(itemID) }
        try assertEditable(target)

        let needed = transition.alignment == .centered
            ? transition.duration / RationalTime(2, 1)
            : transition.duration

        switch edge {
        case .head:
            if let room = availableHead(of: target), room < needed {
                throw MagneticEditError.insufficientHandles(target.name)
            }
        case .tail:
            if let room = availableTail(of: target), room < needed {
                throw MagneticEditError.insufficientHandles(target.name)
            }
        }
        if target.duration < needed {
            throw MagneticEditError.insufficientHandles(target.name)
        }
        try addTransition(transition, to: itemID, edge: edge)
    }

    // MARK: - Roles

    /// Everything carrying a role, grouped — what a stem export walks.
    func itemsByRole() -> [(role: Role, items: [PlacedItem])] {
        var buckets: [String: (Role, [PlacedItem])] = [:]
        for placed in placedItems where !placed.item.content.isGap {
            let key = placed.item.role.fcpxmlValue
            if var existing = buckets[key] {
                existing.1.append(placed)
                buckets[key] = existing
            } else {
                buckets[key] = (placed.item.role, [placed])
            }
        }
        return buckets.values
            .map { (role: $0.0, items: $0.1) }
            .sorted { $0.role.fcpxmlValue < $1.role.fcpxmlValue }
    }

    mutating func setRoleOnAll(matching predicate: (TimelineItem) -> Bool, to role: Role) {
        for index in spine.indices {
            Self.applyRole(&spine[index], role: role, predicate: predicate)
        }
    }

    private static func applyRole(_ item: inout TimelineItem,
                                  role: Role,
                                  predicate: (TimelineItem) -> Bool) {
        if predicate(item) { item.role = role }
        for index in item.connected.indices {
            applyRole(&item.connected[index], role: role, predicate: predicate)
        }
    }

    /// Solo and mute, which in a role-organised timeline are role operations
    /// rather than track ones.
    mutating func setRoleEnabled(_ enabled: Bool, roleName: String) {
        for index in spine.indices {
            Self.applyEnabled(&spine[index], enabled: enabled, roleName: roleName)
        }
    }

    private static func applyEnabled(_ item: inout TimelineItem, enabled: Bool, roleName: String) {
        if item.role.name == roleName { item.isEnabled = enabled }
        for index in item.connected.indices {
            applyEnabled(&item.connected[index], enabled: enabled, roleName: roleName)
        }
    }

    // MARK: - Smart collections

    func items(matching collection: SmartCollection) -> [PlacedItem] {
        placedItems.filter { collection.matches($0) }
    }

    // MARK: - Audio analysis

    /// An honest gain-staging estimate, not a measurement.
    ///
    /// Real LUFS needs audio samples, which do not exist until the conductor has
    /// rendered. What can be checked now is the mix itself: how many things play
    /// at once, at what levels, and whether the sum would clip. That catches the
    /// mistakes that actually happen while cutting.
    struct MixCheck {
        var peakConcurrentGain: Double
        var busiestMoment: RationalTime
        var overlappingCount: Int
        var clippingRisk: Bool
        var roleGains: [(role: String, gain: Double)]

        var headroomDB: Double {
            peakConcurrentGain <= 0 ? 0 : -20 * log10(Swift.max(peakConcurrentGain, 0.0001))
        }
    }

    func checkMix() -> MixCheck {
        let audioItems = placedItems.filter { $0.item.hasAudio && $0.item.isEnabled }
        guard !audioItems.isEmpty else {
            return MixCheck(peakConcurrentGain: 0, busiestMoment: .zero,
                            overlappingCount: 0, clippingRisk: false, roleGains: [])
        }

        // Sample at every edit point: the mix can only change where something
        // starts or stops.
        var samplePoints: [RationalTime] = []
        for placed in audioItems {
            samplePoints.append(placed.start)
            samplePoints.append(placed.end)
        }
        samplePoints = Array(Set(samplePoints)).sorted()

        var peak = 0.0
        var busiest = RationalTime.zero
        var overlapping = 0
        for point in samplePoints {
            var sum = 0.0
            var count = 0
            for placed in audioItems where placed.start <= point && point < placed.end {
                let relative = point - placed.start
                sum += placed.item.audio.gain(at: relative, clipDuration: placed.item.duration)
                count += 1
            }
            if sum > peak {
                peak = sum
                busiest = point
                overlapping = count
            }
        }

        var byRole: [String: Double] = [:]
        for placed in audioItems {
            let gain = placed.item.audio.gain(at: .zero, clipDuration: placed.item.duration)
            byRole[placed.item.role.name, default: 0] += gain
        }

        return MixCheck(peakConcurrentGain: peak,
                        busiestMoment: busiest,
                        overlappingCount: overlapping,
                        clippingRisk: peak > 1.0,
                        roleGains: byRole.map { (role: $0.key, gain: $0.value) }
                            .sorted { $0.gain > $1.gain })
    }

    /// Apply ducking as real keyframes on everything that should step aside for
    /// the trigger role. Turns a mixing chore into one command.
    mutating func applyDucking(_ ducking: Ducking) {
        guard ducking.isEnabled else { return }
        let triggers = placedItems.filter {
            $0.item.role.name == ducking.triggerRole && $0.item.hasAudio && $0.item.isEnabled
        }
        guard !triggers.isEmpty else { return }

        let attack = RationalTime(approximating: ducking.attackMilliseconds / 1000)
        let release = RationalTime(approximating: ducking.releaseMilliseconds / 1000)
        let hold = RationalTime(approximating: ducking.holdMilliseconds / 1000)

        let targets = placedItems.filter {
            $0.item.hasAudio && $0.item.role.name != ducking.triggerRole
        }

        for target in targets {
            let base = target.item.audio.volumeDB.constant
            var animated = target.item.audio.volumeDB
            animated.keyframes.removeAll()

            for trigger in triggers {
                // Only duck where the two actually overlap.
                guard trigger.start < target.end, target.start < trigger.end else { continue }
                let duckIn = RationalTime.max(trigger.start - target.start, .zero)
                let duckOut = RationalTime.min(trigger.end - target.start, target.item.duration)

                animated.setKeyframe(at: RationalTime.max(duckIn - attack, .zero), value: base)
                animated.setKeyframe(at: duckIn, value: base + ducking.amountDB)
                animated.setKeyframe(at: RationalTime.min(duckOut + hold, target.item.duration),
                                     value: base + ducking.amountDB)
                animated.setKeyframe(at: RationalTime.min(duckOut + hold + release, target.item.duration),
                                     value: base)
            }

            guard !animated.keyframes.isEmpty else { continue }
            try? update(id: target.item.id) { item in
                item.audio.volumeDB = animated
                item.audioProcessing.ducking = ducking
            }
        }
    }
}
