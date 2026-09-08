import XCTest
@testable import CinemaComposerPro

/// The behaviours that make this a Final Cut timeline rather than a track
/// timeline. Each one is a property an editor would notice immediately if it
/// broke — sync drifting, a cut landing off frame, a gap opening where none
/// should.
final class MagneticTimelineTests: XCTestCase {

    private let rate = FrameRate.fps24

    private func seconds(_ value: Double) -> RationalTime {
        RationalTime(seconds: value, rate: rate)
    }

    private func clip(_ name: String, _ length: Double, role: Role = .video) -> TimelineItem {
        let media = MediaRef(assetID: name, name: name, sourceDuration: .zero)
        return TimelineItem(name: name, content: .media(media),
                            duration: seconds(length), role: role)
    }

    private func sequence(_ lengths: [Double]) -> MagneticTimeline {
        var timeline = MagneticTimeline(format: TimelineFormat(rate: rate))
        for (index, length) in lengths.enumerated() {
            try? timeline.append(clip("C\(index + 1)", length))
        }
        return timeline
    }

    // MARK: - Exact time

    func testRationalTimeIsExactWhereDoubleDrifts() {
        // A thousand thirtieths must land exactly on 100/3 seconds.
        var total = RationalTime.zero
        for _ in 0..<1000 { total += RationalTime(1, 30) }
        XCTAssertEqual(total, RationalTime(100, 3))
        XCTAssertEqual(total.numerator, 100)
        XCTAssertEqual(total.denominator, 3)
    }

    func testRationalTimeReducesToLowestTerms() {
        let value = RationalTime(1000, 24000)
        XCTAssertEqual(value.numerator, 1)
        XCTAssertEqual(value.denominator, 24)
    }

    func testFcpxmlValueMatchesFinalCutsForm() {
        XCTAssertEqual(RationalTime(1001, 30000).fcpxmlValue, "1001/30000s")
        XCTAssertEqual(RationalTime.zero.fcpxmlValue, "0s")
        XCTAssertEqual(RationalTime(5, 1).fcpxmlValue, "5s")
    }

    func testTimecodeIsNonDropAtTwentyFour() {
        let oneHour = RationalTime(3600, 1)
        XCTAssertEqual(oneHour.timecode(at: .fps24), "01:00:00:00")
    }

    func testDropFrameTimecodeSkipsNumbersNotPictures() {
        // At 29.97 the first dropped numbers are 00:00:59;29 -> 00:01:00;02.
        let rate = FrameRate.fps2997
        let atFrame1800 = rate.frameDuration * 1800
        XCTAssertEqual(atFrame1800.timecode(at: rate), "00:01:00;02")
    }

    func testEverySnapLandsOnAFrameBoundary() {
        let messy = RationalTime(seconds: 1.0 / 7.0, rate: rate)
        let frames = messy.frameCount(at: rate)
        XCTAssertEqual(messy, rate.frameDuration * frames)
    }

    // MARK: - Magnetic storyline

    func testStorylinePositionsAreImplicitAndContiguous() {
        let timeline = sequence([2, 3, 4])
        XCTAssertEqual(timeline.spineStart(at: 0), .zero)
        XCTAssertEqual(timeline.spineStart(at: 1), seconds(2))
        XCTAssertEqual(timeline.spineStart(at: 2), seconds(5))
        XCTAssertEqual(timeline.duration, seconds(9))
    }

    func testRippleDeleteClosesTheGap() throws {
        var timeline = sequence([2, 3, 4])
        let middle = timeline.spine[1].id
        _ = try timeline.rippleDelete(middle)
        XCTAssertEqual(timeline.spine.count, 2)
        XCTAssertEqual(timeline.duration, seconds(6))
        XCTAssertEqual(timeline.spineStart(at: 1), seconds(2))
    }

    func testLiftLeavesAGapAndHoldsTiming() throws {
        var timeline = sequence([2, 3, 4])
        let middle = timeline.spine[1].id
        _ = try timeline.lift(middle)
        XCTAssertEqual(timeline.duration, seconds(9))
        XCTAssertTrue(timeline.spine[1].content.isGap)
        XCTAssertEqual(timeline.spineStart(at: 2), seconds(5))
    }

    /// The whole point of the magnetic model: sound is attached to its picture,
    /// so removing a shot cannot leave the dialogue behind and out of sync.
    func testConnectedAudioTravelsWithItsShot() throws {
        var timeline = sequence([2, 3, 4])
        var dialogue = clip("DX", 3, role: .dialogue)
        dialogue.lane = -1
        timeline.spine[1].connected.append(dialogue)

        XCTAssertEqual(timeline.placed(dialogue.id)?.start, seconds(2))

        // Shorten the clip in front; the dialogue must move with its anchor.
        _ = try timeline.rippleTrim(timeline.spine[0].id, edge: .tail, by: seconds(1))
        XCTAssertEqual(timeline.placed(dialogue.id)?.start, seconds(1))
    }

    func testDeletingAShotTakesItsConnectedAudioWithIt() throws {
        var timeline = sequence([2, 3])
        var dialogue = clip("DX", 3, role: .dialogue)
        dialogue.lane = -1
        let dialogueID = dialogue.id
        timeline.spine[1].connected.append(dialogue)

        _ = try timeline.rippleDelete(timeline.spine[1].id)
        XCTAssertNil(timeline.placed(dialogueID))
    }

    // MARK: - Blade

    func testBladeSplitsWithoutChangingTotalLength() throws {
        var timeline = sequence([6])
        let original = timeline.duration
        _ = try timeline.blade(timeline.spine[0].id, at: seconds(2))
        XCTAssertEqual(timeline.spine.count, 2)
        XCTAssertEqual(timeline.duration, original)
        XCTAssertEqual(timeline.spine[0].duration, seconds(2))
        XCTAssertEqual(timeline.spine[1].duration, seconds(4))
    }

    func testBladeAdvancesTheTailIntoItsSource() throws {
        var timeline = sequence([6])
        _ = try timeline.blade(timeline.spine[0].id, at: seconds(2))
        XCTAssertEqual(timeline.spine[1].sourceIn, seconds(2))
    }

    func testBladeAllCarriesTheCutThroughConnectedLanes() throws {
        var timeline = sequence([6])
        var music = clip("Score", 6, role: .music)
        music.lane = -2
        timeline.spine[0].connected.append(music)

        _ = try timeline.bladeAll(at: seconds(2))
        let audioPieces = timeline.placedItems.filter { $0.item.role.kind == .audio }
        XCTAssertEqual(audioPieces.count, 2)
    }

    // MARK: - The four trims

    func testRippleTrimChangesSequenceLength() throws {
        var timeline = sequence([4, 4])
        _ = try timeline.rippleTrim(timeline.spine[0].id, edge: .tail, by: seconds(1))
        XCTAssertEqual(timeline.duration, seconds(7))
        XCTAssertEqual(timeline.spineStart(at: 1), seconds(3))
    }

    func testRollMovesTheCutButNotTheLength() throws {
        var timeline = sequence([4, 4])
        let total = timeline.duration
        try timeline.roll(betweenItem: timeline.spine[0].id, by: seconds(1))
        XCTAssertEqual(timeline.duration, total)
        XCTAssertEqual(timeline.spine[0].duration, seconds(5))
        XCTAssertEqual(timeline.spine[1].duration, seconds(3))
        XCTAssertEqual(timeline.spine[1].sourceIn, seconds(1))
    }

    func testSlipChangesSourceOnlyAndMovesNothing() throws {
        var timeline = sequence([4, 4])
        let total = timeline.duration
        let target = timeline.spine[1].id
        let startBefore = timeline.placed(target)?.start

        _ = try timeline.slip(target, by: seconds(1))

        XCTAssertEqual(timeline.duration, total)
        XCTAssertEqual(timeline.placed(target)?.start, startBefore)
        XCTAssertEqual(timeline.item(target)?.duration, seconds(4))
        XCTAssertEqual(timeline.item(target)?.sourceIn, seconds(1))
    }

    func testSlideMovesTheClipAndNeighboursAbsorbIt() throws {
        var timeline = sequence([4, 4, 4])
        let total = timeline.duration
        let middle = timeline.spine[1].id

        try timeline.slide(middle, by: seconds(1))

        XCTAssertEqual(timeline.duration, total)
        XCTAssertEqual(timeline.placed(middle)?.start, seconds(5))
        XCTAssertEqual(timeline.item(middle)?.duration, seconds(4))
        XCTAssertEqual(timeline.spine[0].duration, seconds(5))
        XCTAssertEqual(timeline.spine[2].duration, seconds(3))
    }

    func testTrimCannotConsumeAWholeClip() {
        var timeline = sequence([4])
        XCTAssertThrowsError(try timeline.rippleTrim(timeline.spine[0].id,
                                                     edge: .tail, by: seconds(4)))
    }

    // MARK: - Insert / overwrite / connect

    func testInsertPushesEverythingDownstream() throws {
        var timeline = sequence([4, 4])
        _ = try timeline.insert(clip("NEW", 2), at: seconds(4))
        XCTAssertEqual(timeline.duration, seconds(10))
        XCTAssertEqual(timeline.spine[1].name, "NEW")
    }

    func testOverwriteHoldsTheSequenceLength() throws {
        var timeline = sequence([4, 4])
        let total = timeline.duration
        _ = try timeline.overwrite(clip("OVER", 2), at: seconds(1))
        XCTAssertEqual(timeline.duration, total)
    }

    func testConnectAnchorsToTheShotUnderThePlayhead() throws {
        var timeline = sequence([4, 4])
        let connected = try timeline.connect(clip("TITLE", 1), at: seconds(5), lane: 1)
        XCTAssertEqual(timeline.placed(connected.id)?.start, seconds(5))
        XCTAssertEqual(timeline.placed(connected.id)?.anchorID, timeline.spine[1].id)
    }

    // MARK: - Retiming

    func testHalfSpeedDoublesTheTimelineLength() throws {
        var timeline = sequence([4])
        try timeline.setSpeed(timeline.spine[0].id, percent: 50)
        XCTAssertEqual(timeline.spine[0].duration, seconds(8))
        XCTAssertEqual(timeline.spine[0].sourceUsed, seconds(4))
    }

    func testClearingRetimeRestoresTheSourceLength() throws {
        var timeline = sequence([4])
        let id = timeline.spine[0].id

        // Double speed halves the time it occupies but still consumes 4s of source.
        try timeline.setSpeed(id, percent: 200)
        XCTAssertEqual(timeline.spine[0].duration, seconds(2))
        XCTAssertEqual(timeline.spine[0].sourceUsed, seconds(4))

        // Resetting plays that source at 100%, so it takes its full 4s back.
        try timeline.clearRetime(id)
        XCTAssertEqual(timeline.spine[0].duration, seconds(4))
        XCTAssertNil(timeline.spine[0].retime)
    }

    // MARK: - Auditions carry cost

    func testPickingATakeMovesWhatTheCutCost() throws {
        var timeline = sequence([4])
        let id = timeline.spine[0].id
        let cheap = Take(toolID: "cheap", cost: 10)
        let dear = Take(toolID: "dear", cost: 90)
        try timeline.addTake(cheap, to: id)
        try timeline.addTake(dear, to: id)

        XCTAssertEqual(timeline.costOfCut, 90, accuracy: 0.001)
        XCTAssertEqual(timeline.costOfUnusedTakes, 10, accuracy: 0.001)

        try timeline.selectTake(cheap.id, on: id)
        XCTAssertEqual(timeline.costOfCut, 10, accuracy: 0.001)
        XCTAssertEqual(timeline.costOfUnusedTakes, 90, accuracy: 0.001)
    }

    // MARK: - Compounds

    func testCompoundNestsAndBreakingApartRestores() throws {
        var timeline = sequence([2, 3, 4])
        let ids = [timeline.spine[0].id, timeline.spine[1].id]
        let compound = try timeline.makeCompound(from: ids, name: "Scene 1")

        XCTAssertEqual(timeline.spine.count, 2)
        XCTAssertEqual(compound.duration, seconds(5))
        XCTAssertEqual(timeline.duration, seconds(9))

        try timeline.breakApart(compound.id)
        XCTAssertEqual(timeline.spine.count, 3)
        XCTAssertEqual(timeline.duration, seconds(9))
    }

    func testNonContiguousSelectionCannotCompound() {
        var timeline = sequence([2, 3, 4])
        let ids = [timeline.spine[0].id, timeline.spine[2].id]
        XCTAssertThrowsError(try timeline.makeCompound(from: ids, name: "Nope"))
    }

    // MARK: - Split edits

    func testDetachedAudioBecomesAConnectedClipThatCanLead() throws {
        var timeline = sequence([4, 4])
        let detached = try timeline.detachAudio(from: timeline.spine[1].id, lead: seconds(1))
        let placed = timeline.placed(detached.id)
        XCTAssertEqual(placed?.lane, -1)
        // A J-cut: the sound starts a second before the picture it belongs to.
        XCTAssertEqual(placed?.start, seconds(3))
    }

    // MARK: - Validation

    func testAValidSequenceReportsNoProblems() throws {
        var timeline = sequence([2, 3, 4])
        _ = try timeline.blade(timeline.spine[1].id, at: seconds(3))
        XCTAssertTrue(timeline.validate().isEmpty, "\(timeline.validate())")
    }

    // MARK: - FCPXML

    func testFcpxmlCarriesLanesRolesAndExactTimes() throws {
        var timeline = sequence([4])
        var dialogue = clip("DX", 4, role: .dialogue)
        dialogue.lane = -1
        timeline.spine[0].connected.append(dialogue)

        let xml = FCPXMLExporter.export(timeline)

        XCTAssertTrue(xml.contains("<fcpxml version=\"1.10\">"))
        XCTAssertTrue(xml.contains("lane=\"-1\""))
        XCTAssertTrue(xml.contains("audioRole=\"Dialogue\""))
        XCTAssertTrue(xml.contains("frameDuration=\"1/24s\""))
        XCTAssertFalse(xml.contains("nan"))
    }

    /// A nested clip's offset is written in its parent's local timeline, whose
    /// origin is the parent's own `start`. Getting this wrong is why connected
    /// clips drift in other exporters.
    func testNestedOffsetIsRebasedOntoTheParentStart() throws {
        var timeline = sequence([8])
        timeline.spine[0].sourceIn = seconds(2)
        var title = clip("TITLE", 1, role: .titles)
        title.lane = 1
        title.offset = seconds(3)
        timeline.spine[0].connected.append(title)

        let xml = FCPXMLExporter.export(timeline)
        // Parent start 2s + child offset 3s = 5s in the parent's local timeline.
        XCTAssertTrue(xml.contains("offset=\"5s\""), xml)
    }

    // MARK: - Undo

    @MainActor
    func testUndoRestoresTheExactPriorCut() {
        let doc = CutDocument(timeline: sequence([4, 4]))
        let before = doc.timeline

        doc.playhead = seconds(2)
        doc.bladeAtPlayhead()
        XCTAssertEqual(doc.timeline.spine.count, 3)

        doc.undo()
        XCTAssertEqual(doc.timeline, before)
        XCTAssertTrue(doc.canRedo)

        doc.redo()
        XCTAssertEqual(doc.timeline.spine.count, 3)
    }

    @MainActor
    func testAFailedEditCommitsNothingAndKeepsUndoClean() {
        let doc = CutDocument(timeline: sequence([4]))
        let before = doc.timeline

        doc.perform("Impossible Trim") { timeline in
            _ = try timeline.rippleTrim(timeline.spine[0].id, edge: .tail, by: self.seconds(10))
        }

        XCTAssertEqual(doc.timeline, before)
        XCTAssertFalse(doc.canUndo)
        XCTAssertNotNil(doc.lastError)
    }
}
