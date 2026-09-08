import Foundation

/// One undoable step. Snapshots rather than inverse operations: the timeline is
/// a value type, so a snapshot is both trivially correct and cheap — the arrays
/// an edit did not touch are shared by copy-on-write.
private struct UndoStep {
    var name: String
    var timeline: MagneticTimeline
    var selection: Set<String>
    var playhead: RationalTime
}

/// The cutting-room session: the sequence, where the playhead is, what is
/// selected, and every edit that got you here.
///
/// Final Cut's editing model is stateful in ways the timeline struct is not —
/// a blade happens *at the playhead*, a connect lands *on the selected lane* —
/// so that state lives here and the struct stays a pure value.
@MainActor
final class CutDocument: ObservableObject {

    /// Resolving every item to absolute time walks the whole tree, so it is
    /// cached here rather than recomputed on each SwiftUI body evaluation — a
    /// feature-length cut is thousands of items.
    @Published private(set) var timeline: MagneticTimeline {
        didSet { placed = timeline.placedItems }
    }
    @Published private(set) var placed: [PlacedItem] = []
    @Published var selection: Set<String> = []
    @Published var playhead: RationalTime = .zero
    @Published var inPoint: RationalTime?
    @Published var outPoint: RationalTime?
    @Published var isSnappingOn: Bool = true
    @Published var targetLane: Int = 1
    @Published private(set) var lastError: String?

    private var undoStack: [UndoStep] = []
    private var redoStack: [UndoStep] = []
    private let undoLimit = 200

    init(timeline: MagneticTimeline = MagneticTimeline()) {
        self.timeline = timeline
        self.placed = timeline.placedItems
        self.selection = timeline.spine.first.map { [$0.id] } ?? []
    }

    var rate: FrameRate { timeline.format.rate }

    // MARK: - Undo

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var undoName: String? { undoStack.last?.name }
    var redoName: String? { redoStack.last?.name }

    /// Run an edit as one undoable step. A throwing edit leaves the timeline
    /// exactly as it was — the snapshot is only committed on success.
    func perform(_ name: String, _ edit: (inout MagneticTimeline) throws -> Void) {
        let snapshot = UndoStep(name: name, timeline: timeline,
                                selection: selection, playhead: playhead)
        var working = timeline
        do {
            try edit(&working)
        } catch {
            lastError = error.localizedDescription
            return
        }
        working.snapToFrames()
        let problems = working.validate()
        if let first = problems.first {
            lastError = first
            return
        }
        undoStack.append(snapshot)
        if undoStack.count > undoLimit { undoStack.removeFirst() }
        redoStack.removeAll()
        timeline = working
        lastError = nil
    }

    func undo() {
        guard let step = undoStack.popLast() else { return }
        redoStack.append(UndoStep(name: step.name, timeline: timeline,
                                  selection: selection, playhead: playhead))
        timeline = step.timeline
        selection = step.selection
        playhead = step.playhead
    }

    func redo() {
        guard let step = redoStack.popLast() else { return }
        undoStack.append(UndoStep(name: step.name, timeline: timeline,
                                  selection: selection, playhead: playhead))
        timeline = step.timeline
        selection = step.selection
        playhead = step.playhead
    }

    func replaceTimeline(_ new: MagneticTimeline, name: String = "Rebuild") {
        perform(name) { $0 = new }
    }

    func clearError() { lastError = nil }

    // MARK: - Selection & playhead

    var selectedItems: [PlacedItem] {
        placed.filter { selection.contains($0.item.id) }
    }

    var primarySelection: PlacedItem? {
        selectedItems.sorted { $0.start < $1.start }.first
    }

    func select(_ itemID: String, extending: Bool = false) {
        if extending {
            if selection.contains(itemID) { selection.remove(itemID) } else { selection.insert(itemID) }
        } else {
            selection = [itemID]
        }
        if let placed = timeline.placed(itemID), !extending {
            playhead = placed.start
        }
    }

    func selectAll() { selection = Set(placed.map(\.item.id)) }

    /// Hit test: what sits on this lane at this time. The timeline view maps a
    /// tap straight into these coordinates.
    func item(onLane lane: Int, at time: RationalTime) -> PlacedItem? {
        placed.first { $0.lane == lane && $0.start <= time && time < $0.end }
    }

    /// Lanes top to bottom, the way the timeline draws them. Lane 0 — the
    /// primary storyline — is always present even in an empty sequence.
    var laneOrder: [Int] {
        var lanes = Set(placed.map(\.lane))
        lanes.insert(0)
        return lanes.sorted(by: >)
    }
    func deselectAll() { selection = [] }

    /// Every point where something starts or ends — what the playhead steps
    /// between and what snapping pulls toward.
    var editPoints: [RationalTime] {
        var points: Set<RationalTime> = [.zero]
        for entry in placed {
            points.insert(entry.start)
            points.insert(entry.end)
        }
        for entry in timeline.allMarkers { points.insert(entry.at) }
        return points.sorted()
    }

    func goToNextEdit() {
        if let next = editPoints.first(where: { playhead < $0 }) { playhead = next }
    }

    func goToPreviousEdit() {
        if let previous = editPoints.last(where: { $0 < playhead }) { playhead = previous }
    }

    func step(frames: Int64) {
        let moved = playhead + rate.frameDuration * frames
        playhead = moved.isNegative ? .zero : moved
    }

    func goToStart() { playhead = .zero }
    func goToEnd() { playhead = timeline.contentEnd }

    /// Pull a dragged time to the nearest edit point when it is close enough.
    func snap(_ time: RationalTime, withinFrames tolerance: Int64 = 8) -> RationalTime {
        let snapped = time.snapped(to: rate)
        guard isSnappingOn else { return snapped }
        let window = rate.frameDuration * tolerance
        var best = snapped
        var bestDistance = window
        for point in editPoints {
            let delta = point < snapped ? snapped - point : point - snapped
            if delta < bestDistance {
                bestDistance = delta
                best = point
            }
        }
        return best
    }

    // MARK: - In / out

    func markIn() { inPoint = playhead }
    func markOut() { outPoint = playhead }
    func clearInOut() { inPoint = nil; outPoint = nil }

    var markedRange: (start: RationalTime, duration: RationalTime)? {
        guard let inPoint, let outPoint, inPoint < outPoint else { return nil }
        return (inPoint, outPoint - inPoint)
    }

    // MARK: - Edits

    func bladeAtPlayhead(allLanes: Bool = false) {
        let at = playhead
        perform(allLanes ? "Blade All" : "Blade") { timeline in
            if allLanes {
                _ = try timeline.bladeAll(at: at)
            } else {
                guard let target = timeline.storylineItem(at: at) else { return }
                _ = try timeline.blade(target.item.id, at: at)
            }
        }
    }

    func deleteSelection(rippling: Bool) {
        let ids = selection
        guard !ids.isEmpty else { return }
        perform(rippling ? "Ripple Delete" : "Replace with Gap") { timeline in
            for id in ids {
                if rippling {
                    _ = try? timeline.rippleDelete(id)
                } else {
                    _ = try? timeline.lift(id)
                }
            }
            timeline.tidy()
        }
        selection = []
    }

    func trimSelection(edge: EditEdge, frames: Int64) {
        guard let target = primarySelection else { return }
        let delta = rate.frameDuration * frames
        perform("Ripple Trim") { timeline in
            _ = try timeline.rippleTrim(target.item.id, edge: edge, by: delta)
        }
    }

    func rollSelection(frames: Int64) {
        guard let target = primarySelection else { return }
        let delta = rate.frameDuration * frames
        perform("Roll Edit") { timeline in
            try timeline.roll(betweenItem: target.item.id, by: delta)
        }
    }

    func slipSelection(frames: Int64) {
        guard let target = primarySelection else { return }
        let delta = rate.frameDuration * frames
        perform("Slip") { timeline in
            _ = try timeline.slip(target.item.id, by: delta)
        }
    }

    func slideSelection(frames: Int64) {
        guard let target = primarySelection else { return }
        let delta = rate.frameDuration * frames
        perform("Slide") { timeline in
            try timeline.slide(target.item.id, by: delta)
        }
    }

    func insertAtPlayhead(_ item: TimelineItem) {
        let at = playhead
        perform("Insert") { timeline in
            _ = try timeline.insert(item, at: at)
        }
    }

    func overwriteAtPlayhead(_ item: TimelineItem) {
        let at = playhead
        perform("Overwrite") { timeline in
            _ = try timeline.overwrite(item, at: at)
        }
    }

    func connectAtPlayhead(_ item: TimelineItem) {
        let at = playhead
        let lane = targetLane
        perform("Connect") { timeline in
            _ = try timeline.connect(item, at: at, lane: lane)
        }
    }

    func appendToStoryline(_ item: TimelineItem) {
        perform("Append") { timeline in
            _ = try timeline.append(item)
        }
    }

    func detachAudioFromSelection(leadFrames: Int64 = 0) {
        guard let target = primarySelection else { return }
        let lead = rate.frameDuration * leadFrames
        perform("Detach Audio") { timeline in
            _ = try timeline.detachAudio(from: target.item.id, lead: lead)
        }
    }

    func makeCompoundFromSelection(named name: String) {
        let ids = Array(selection)
        guard ids.count > 1 else { return }
        perform("New Compound Clip") { timeline in
            _ = try timeline.makeCompound(from: ids, name: name)
        }
    }

    func breakApartSelection() {
        guard let target = primarySelection else { return }
        perform("Break Apart") { timeline in
            try timeline.breakApart(target.item.id)
        }
    }

    func setSpeedOnSelection(percent: Double) {
        guard let target = primarySelection else { return }
        perform("Change Speed") { timeline in
            try timeline.setSpeed(target.item.id, percent: percent)
        }
    }

    func setSpeedRampOnSelection(from: Double, to: Double) {
        guard let target = primarySelection else { return }
        perform("Speed Ramp") { timeline in
            try timeline.setSpeedRamp(target.item.id, fromPercent: from, toPercent: to)
        }
    }

    func clearSpeedOnSelection() {
        guard let target = primarySelection else { return }
        perform("Reset Speed") { timeline in
            try timeline.clearRetime(target.item.id)
        }
    }

    func toggleEnabledOnSelection() {
        guard let target = primarySelection else { return }
        let enabled = !target.item.isEnabled
        perform(enabled ? "Enable Clip" : "Disable Clip") { timeline in
            try timeline.setEnabled(enabled, on: target.item.id)
        }
    }

    func toggleLockOnSelection() {
        guard let target = primarySelection else { return }
        let locked = !target.item.isLocked
        perform(locked ? "Lock Clip" : "Unlock Clip") { timeline in
            try timeline.setLocked(locked, on: target.item.id)
        }
    }

    func rateSelection(_ rating: Rating?) {
        guard let target = primarySelection else { return }
        perform(rating?.label ?? "Clear Rating") { timeline in
            try timeline.setRating(rating, on: target.item.id)
        }
    }

    func setRoleOnSelection(_ role: Role) {
        guard let target = primarySelection else { return }
        perform("Assign Role") { timeline in
            try timeline.setRole(role, on: target.item.id)
        }
    }

    func addMarkerAtPlayhead(name: String, kind: EditMarkerKind = .standard, note: String = "") {
        let at = playhead
        perform("Add Marker") { timeline in
            guard let target = timeline.storylineItem(at: at) else {
                timeline.markers.append(EditMarker(at: at, name: name, note: note, kind: kind))
                return
            }
            let relative = at - target.start
            try timeline.addMarker(EditMarker(at: relative, name: name, note: note, kind: kind),
                                   to: target.item.id)
        }
    }

    func addTransitionToSelection(edge: EditEdge) {
        guard let target = primarySelection else { return }
        let transition = EditTransition.standard(rate: rate)
        perform("Add Cross Dissolve") { timeline in
            try timeline.addTransition(transition, to: target.item.id, edge: edge)
        }
    }

    func setFadeOnSelection(edge: EditEdge, seconds: Double, shape: FadeShape = .easeIn) {
        guard let target = primarySelection else { return }
        let fade = Fade(duration: RationalTime(seconds: seconds, rate: rate), shape: shape)
        perform("Set Fade") { timeline in
            try timeline.setFade(fade, on: target.item.id, edge: edge)
        }
    }

    func selectTake(_ takeID: String, on itemID: String) {
        perform("Select Take") { timeline in
            try timeline.selectTake(takeID, on: itemID)
        }
    }

    func addTake(_ take: Take, to itemID: String) {
        perform("Add Take") { timeline in
            try timeline.addTake(take, to: itemID)
        }
    }
}
