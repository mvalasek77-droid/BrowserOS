import Foundation

/// What a timeline item actually is. The recursion into `compound` goes through
/// an array, which gives Swift the indirection it needs without boxing.
enum ItemContent: Codable, Equatable {
    case media(MediaRef)
    case gap
    case title(text: String)
    case compound(items: [TimelineItem])

    var isGap: Bool { if case .gap = self { return true }; return false }

    var isCompound: Bool { if case .compound = self { return true }; return false }

    var mediaRef: MediaRef? {
        if case .media(let ref) = self { return ref }
        return nil
    }

    var symbol: String {
        switch self {
        case .media: return "film"
        case .gap: return "rectangle.dashed"
        case .title: return "textformat"
        case .compound: return "square.stack.3d.down.right"
        }
    }
}

/// One item in a sequence.
///
/// In the primary storyline an item's start is implicit — it begins where the
/// previous one ends, which is what makes the timeline magnetic. A *connected*
/// item instead carries a `lane` (positive above the storyline, negative below)
/// and an `offset` measured from its anchor's start, so it travels with the
/// shot it belongs to rather than sitting at a fixed time.
struct TimelineItem: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var content: ItemContent

    /// Timeline length. With retiming active this is the retimed length, not
    /// the amount of source consumed.
    var duration: RationalTime
    var sourceIn: RationalTime = .zero

    /// 0 for storyline items; ±n for connected items.
    var lane: Int = 0
    /// For connected items only: distance from the anchor's start. Negative
    /// values are legal and are how a J-cut reaches back before the picture.
    var offset: RationalTime = .zero

    var role: Role = .video
    var isEnabled: Bool = true
    var isLocked: Bool = false

    var transform: Transform = Transform()
    var audio: AudioSettings = AudioSettings()
    var retime: Retime?

    var transitionIn: EditTransition?
    var transitionOut: EditTransition?

    var markers: [EditMarker] = []
    var keywords: [Keyword] = []
    var rating: Rating?
    var audition: Audition?
    var notes: String = ""

    /// Clips hanging off this one. Each carries its own lane and offset.
    var connected: [TimelineItem] = []

    var provenance: Provenance = Provenance()

    init(name: String,
         content: ItemContent,
         duration: RationalTime,
         sourceIn: RationalTime = .zero,
         role: Role = .video) {
        self.name = name
        self.content = content
        self.duration = duration
        self.sourceIn = sourceIn
        self.role = role
    }

    // MARK: - Derived

    /// How much source this item consumes. Retiming decouples it from `duration`.
    var sourceUsed: RationalTime {
        if let retime, retime.isActive {
            return retime.segments.reduce(RationalTime.zero) { $0 + ($1.sourceEnd - $1.sourceStart) }
        }
        return duration
    }

    var sourceOut: RationalTime { sourceIn + sourceUsed }

    var hasAudio: Bool {
        if role.kind == .audio { return true }
        return content.mediaRef?.hasAudio ?? false
    }

    /// The cost carried by the selected take, so a cut is also a bill.
    var cost: Double { audition?.selected?.cost ?? provenance.cost }

    var costOfDiscardedTakes: Double { audition?.costOfDiscarded ?? 0 }

    var speedLabel: String? {
        guard let retime, retime.isActive else { return nil }
        return retime.displayRate
    }

    /// Every item under this one, this item included, depth first.
    var selfAndDescendants: [TimelineItem] {
        var found = [self]
        for child in connected { found.append(contentsOf: child.selfAndDescendants) }
        if case .compound(let items) = content {
            for nested in items { found.append(contentsOf: nested.selfAndDescendants) }
        }
        return found
    }

    // MARK: - Factories

    static func gap(duration: RationalTime) -> TimelineItem {
        TimelineItem(name: "Gap", content: .gap, duration: duration)
    }

    static func title(_ text: String, duration: RationalTime) -> TimelineItem {
        var item = TimelineItem(name: text, content: .title(text: text), duration: duration, role: .titles)
        item.lane = 1
        return item
    }
}

/// Sequence settings — the "project properties" sheet.
struct TimelineFormat: Codable, Equatable {
    var rate: FrameRate = .fps24
    var resolution: Resolution = Resolution(width: 1920, height: 1080)
    var colorSpace: String = "Rec. 709"

    var label: String { "\(resolution.label) · \(rate.label) fps · \(colorSpace)" }
}

/// An item resolved to absolute time — what the timeline view draws and what
/// the exporter walks.
struct PlacedItem: Identifiable {
    var item: TimelineItem
    var start: RationalTime
    var lane: Int
    var anchorID: String?

    var id: String { item.id }
    var end: RationalTime { start + item.duration }
    var isConnected: Bool { anchorID != nil }
}

enum MagneticEditError: LocalizedError {
    case noSuchItem(String)
    case itemLocked(String)
    case bladeOutsideItem
    case trimConsumesItem
    case nonPositiveDuration
    case notInStoryline(String)
    case noRoomToTrim
    case cannotNestSelection

    var errorDescription: String? {
        switch self {
        case .noSuchItem(let id): return "No item \(id) in this sequence"
        case .itemLocked(let name): return "\(name) is locked"
        case .bladeOutsideItem: return "The blade point is outside that clip"
        case .trimConsumesItem: return "That trim would consume the whole clip"
        case .nonPositiveDuration: return "A clip needs a positive duration"
        case .notInStoryline(let id): return "\(id) is a connected clip, not part of the primary storyline"
        case .noRoomToTrim: return "There is no media left to trim into"
        case .cannotNestSelection: return "Select clips in the primary storyline to make a compound"
        }
    }
}

/// The magnetic timeline.
///
/// Final Cut's model, not Avid's: a primary storyline that cannot contain
/// overlaps or accidental gaps, and connected clips that hang off it by lane.
/// Deleting from the storyline closes the hole; everything attached moves with
/// the shot it was attached to. Tracks — and the whole class of bugs where audio
/// slips out of sync with its picture — simply do not exist here.
struct MagneticTimeline: Codable, Equatable {
    var name: String = "Sequence 1"
    var format: TimelineFormat = TimelineFormat()
    var spine: [TimelineItem] = []
    var roles: [Role] = Role.standard
    var markers: [EditMarker] = []

    init(name: String = "Sequence 1", format: TimelineFormat = TimelineFormat()) {
        self.name = name
        self.format = format
    }

    var rate: FrameRate { format.rate }

    // MARK: - Reading

    var duration: RationalTime {
        spine.reduce(RationalTime.zero) { $0 + $1.duration }
    }

    /// The furthest point anything reaches, connected clips included — a
    /// connected title can legally overhang the end of the storyline.
    var contentEnd: RationalTime {
        placedItems.reduce(RationalTime.zero) { RationalTime.max($0, $1.end) }
    }

    var itemCount: Int { spine.reduce(0) { $0 + $1.selfAndDescendants.count } }

    var storylineCount: Int { spine.count }

    var costOfCut: Double {
        placedItems.reduce(0) { $0 + $1.item.cost }
    }

    var costOfUnusedTakes: Double {
        placedItems.reduce(0) { $0 + $1.item.costOfDiscardedTakes }
    }

    /// Where a storyline item begins. Implicit position is the whole point of a
    /// magnetic timeline, so it is derived rather than stored.
    func spineStart(at index: Int) -> RationalTime {
        guard index > 0, index <= spine.count else { return .zero }
        return spine[0..<index].reduce(RationalTime.zero) { $0 + $1.duration }
    }

    func spineIndex(of itemID: String) -> Int? {
        spine.firstIndex { $0.id == itemID }
    }

    /// Every item resolved to absolute time, storyline and connected alike.
    var placedItems: [PlacedItem] {
        var placed: [PlacedItem] = []
        var cursor = RationalTime.zero
        for item in spine {
            placed.append(PlacedItem(item: item, start: cursor, lane: 0, anchorID: nil))
            appendConnected(of: item, anchoredAt: cursor, into: &placed)
            cursor += item.duration
        }
        return placed
    }

    private func appendConnected(of anchor: TimelineItem,
                                 anchoredAt anchorStart: RationalTime,
                                 into placed: inout [PlacedItem]) {
        for child in anchor.connected {
            let start = anchorStart + child.offset
            placed.append(PlacedItem(item: child, start: start, lane: child.lane, anchorID: anchor.id))
            appendConnected(of: child, anchoredAt: start, into: &placed)
        }
    }

    func placed(_ itemID: String) -> PlacedItem? {
        placedItems.first { $0.item.id == itemID }
    }

    func item(_ itemID: String) -> TimelineItem? {
        placed(itemID)?.item
    }

    /// Lanes actually in use, top to bottom the way the timeline draws them.
    var occupiedLanes: [Int] {
        let lanes = Set(placedItems.map(\.lane))
        return lanes.sorted(by: >)
    }

    /// The storyline item under a point in time — what a connected clip anchors
    /// to and what the playhead is parked on.
    func storylineItem(at time: RationalTime) -> (index: Int, item: TimelineItem, start: RationalTime)? {
        var cursor = RationalTime.zero
        for (index, item) in spine.enumerated() {
            let end = cursor + item.duration
            if cursor <= time, time < end { return (index, item, cursor) }
            cursor = end
        }
        if let last = spine.indices.last {
            return (last, spine[last], spineStart(at: last))
        }
        return nil
    }

    func items(withRole role: Role) -> [PlacedItem] {
        placedItems.filter { $0.item.role.name == role.name }
    }

    func items(rated rating: Rating) -> [PlacedItem] {
        placedItems.filter { $0.item.rating == rating }
    }

    /// Every marker in the sequence, resolved to absolute time.
    var allMarkers: [(marker: EditMarker, at: RationalTime, itemName: String)] {
        var found = markers.map { ($0, $0.at, name) }
        for placed in placedItems {
            for marker in placed.item.markers {
                found.append((marker, placed.start + marker.at, placed.item.name))
            }
        }
        return found.sorted { $0.1 < $1.1 }
    }

    // MARK: - Locating for mutation

    /// Find an item anywhere in the tree and hand back a writable path to it.
    /// Storyline items have a single-element path; a connected clip's path walks
    /// down through its anchors.
    func path(to itemID: String) -> [Int]? {
        for (index, item) in spine.enumerated() {
            if let sub = Self.path(to: itemID, in: item) { return [index] + sub }
        }
        return nil
    }

    private static func path(to itemID: String, in item: TimelineItem) -> [Int]? {
        if item.id == itemID { return [] }
        for (index, child) in item.connected.enumerated() {
            if let sub = path(to: itemID, in: child) { return [index] + sub }
        }
        return nil
    }

    /// Read an item at a path produced by `path(to:)`.
    func item(at path: [Int]) -> TimelineItem? {
        guard let first = path.first, spine.indices.contains(first) else { return nil }
        var current = spine[first]
        for step in path.dropFirst() {
            guard current.connected.indices.contains(step) else { return nil }
            current = current.connected[step]
        }
        return current
    }

    /// Apply a change to the item at a path, however deeply connected it is.
    mutating func update(at path: [Int], _ change: (inout TimelineItem) throws -> Void) rethrows {
        guard let first = path.first, spine.indices.contains(first) else { return }
        try Self.update(&spine[first], path: Array(path.dropFirst()), change)
    }

    private static func update(_ item: inout TimelineItem,
                               path: [Int],
                               _ change: (inout TimelineItem) throws -> Void) rethrows {
        guard let first = path.first else {
            try change(&item)
            return
        }
        guard item.connected.indices.contains(first) else { return }
        try update(&item.connected[first], path: Array(path.dropFirst()), change)
    }

    mutating func update(id itemID: String, _ change: (inout TimelineItem) throws -> Void) throws {
        guard let path = path(to: itemID) else { throw MagneticEditError.noSuchItem(itemID) }
        try update(at: path, change)
    }

    /// Detach an item from wherever it lives and return it.
    @discardableResult
    mutating func detach(_ itemID: String) throws -> TimelineItem {
        guard let path = path(to: itemID) else { throw MagneticEditError.noSuchItem(itemID) }
        if path.count == 1 {
            return spine.remove(at: path[0])
        }
        let parentPath = Array(path.dropLast())
        let childIndex = path[path.count - 1]
        var removed: TimelineItem?
        update(at: parentPath) { parent in
            guard parent.connected.indices.contains(childIndex) else { return }
            removed = parent.connected.remove(at: childIndex)
        }
        guard let removed else { throw MagneticEditError.noSuchItem(itemID) }
        return removed
    }

    // MARK: - Housekeeping

    /// Snap every boundary to the sequence's frame grid. Cheap insurance: an
    /// edit computed from a drag in points should never leave a sub-frame sliver.
    mutating func snapToFrames() {
        for index in spine.indices {
            Self.snap(&spine[index], to: rate)
        }
    }

    private static func snap(_ item: inout TimelineItem, to rate: FrameRate) {
        item.duration = item.duration.snapped(to: rate)
        item.sourceIn = item.sourceIn.snapped(to: rate)
        item.offset = item.offset.snapped(to: rate)
        for index in item.connected.indices {
            snap(&item.connected[index], to: rate)
        }
    }

    /// Problems that are editor bugs rather than user errors. The storyline
    /// cannot overlap by construction, so this checks what construction cannot.
    func validate() -> [String] {
        var problems: [String] = []
        for item in spine {
            if item.duration.isNegative || item.duration.isZero {
                problems.append("\(item.name) has no duration")
            }
            if item.sourceIn.isNegative {
                problems.append("\(item.name) starts before the head of its source")
            }
            if let ref = item.content.mediaRef, !ref.sourceDuration.isZero,
               ref.sourceDuration < item.sourceOut {
                problems.append("\(item.name) reads past the end of its source")
            }
            for child in item.connected where child.lane == 0 {
                problems.append("\(child.name) is connected but sits in lane 0")
            }
        }
        var seen = Set<String>()
        for placed in placedItems {
            if !seen.insert(placed.item.id).inserted {
                problems.append("\(placed.item.name) appears twice")
            }
        }
        return problems
    }
}
