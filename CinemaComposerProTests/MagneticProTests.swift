import XCTest
@testable import CinemaComposerPro

/// The hardening and the pro feature layer. These are the failures that would
/// be quietest in the field — a comparison inverting, a saved project refusing
/// to open, a grade landing a second late — so they are pinned down here.
final class MagneticProTests: XCTestCase {

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

    // MARK: - Overflow hardening

    /// The bug that would be hardest to see: denominators large enough that a
    /// naive cross-multiply overflows and the comparison comes back *inverted*.
    /// Clips would sort backwards and hit-testing would pick the wrong one.
    func testComparisonSurvivesDenominatorsThatOverflowACrossMultiply() {
        let a = RationalTime(10_000_000_000, 999_999_937)
        let b = RationalTime(10_000_000_001, 999_999_893)

        // Confirm the naive product really would overflow.
        let (_, overflows) = Int64(10_000_000_000).multipliedReportingOverflow(by: 999_999_893)
        XCTAssertTrue(overflows, "test no longer exercises the overflow path")

        XCTAssertTrue(a < b)
        XCTAssertFalse(b < a)
        XCTAssertTrue(a.seconds < b.seconds)
    }

    func testArithmeticNeverWrapsIntoNonsense() {
        var total = RationalTime.zero
        // Deliberately awkward, mutually prime timebases.
        for denominator in [7, 11, 13, 17, 19, 23, 29, 31, 37, 41] {
            total += RationalTime(1, Int64(denominator))
        }
        XCTAssertFalse(total.isNegative)
        // The exact sum is 0.5838…; the point is that it is still sane.
        XCTAssertEqual(total.seconds, 0.5838, accuracy: 0.001)
    }

    func testLimitingDenominatorStaysCloseToTheOriginal() {
        let precise = RationalTime(1_234_567, 7_654_321)
        let limited = precise.limitingDenominator(to: 1000)
        XCTAssertLessThanOrEqual(limited.denominator, 1000)
        XCTAssertEqual(limited.seconds, precise.seconds, accuracy: 0.001)
    }

    func testNegatingTheExtremeValueDoesNotTrap() {
        let extreme = RationalTime(Int64.min, 1)
        let negated = -extreme
        XCTAssertEqual(negated, .zero)
        XCTAssertFalse(extreme.magnitude.isNegative)
    }

    func testZeroFrameDurationCannotReachADivide() {
        let rate = FrameRate(frameDuration: .zero)
        XCTAssertFalse(rate.frameDuration.isZero)
        XCTAssertGreaterThan(rate.nominalRate, 0)
    }

    func testTimecodeRoundTrips() {
        let original = RationalTime(seconds: 3725.5, rate: .fps24)
        let text = original.timecode(at: .fps24)
        let parsed = RationalTime(timecode: text, rate: .fps24)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.timecode(at: .fps24), text)
    }

    // MARK: - Schema tolerance

    /// A project saved before a field existed must still open. Swift's
    /// synthesized decoder fails on a missing key, and the cut lives inside the
    /// project file — so a strict decoder loses the whole document, not just
    /// the new field.
    func testAnItemDecodesWhenNewerFieldsAreAbsent() throws {
        let legacy = """
        {"content":{"gap":{}},"duration":{"numerator":4,"denominator":1}}
        """
        let data = Data(legacy.utf8)
        let item = try JSONDecoder().decode(TimelineItem.self, from: data)

        XCTAssertEqual(item.duration, RationalTime(4, 1))
        XCTAssertTrue(item.content.isGap)
        XCTAssertTrue(item.effects.isEmpty)
        XCTAssertTrue(item.color.isNeutral)
        XCTAssertFalse(item.isAdjustmentLayer)
        XCTAssertTrue(item.isEnabled)
        XCTAssertFalse(item.id.isEmpty)
    }

    func testAnItemSurvivesAFullEncodeDecodeRound() throws {
        var item = clip("SHOT", 4)
        item.color.saturation.constant = 130
        item.effects = [EffectLibrary.gaussianBlur]
        item.notes = "watch the eyeline"

        let data = try JSONEncoder().encode(item)
        let restored = try JSONDecoder().decode(TimelineItem.self, from: data)

        XCTAssertEqual(restored.name, "SHOT")
        XCTAssertEqual(restored.color.saturation.constant, 130)
        XCTAssertEqual(restored.effects.count, 1)
        XCTAssertEqual(restored.notes, "watch the eyeline")
    }

    // MARK: - Keyframes follow the picture

    func testTrimmingTheHeadShiftsGradeAndEffectKeyframesToo() throws {
        var timeline = sequence([8])
        let id = timeline.spine[0].id

        try timeline.update(id: id) { item in
            item.color.exposure.setKeyframe(at: self.seconds(4), value: 1.0)
            var blur = EffectLibrary.gaussianBlur
            if case .number(var animatable) = blur.parameters[0].value {
                animatable.setKeyframe(at: self.seconds(4), value: 50)
                blur.parameters[0].value = .number(animatable)
            }
            item.effects = [blur]
        }

        _ = try timeline.rippleTrim(id, edge: .head, by: seconds(2))

        let trimmed = try XCTUnwrap(timeline.item(id))
        // The keyframe was 4s into the clip; after cutting 2s off the head it
        // must sit 2s in, still on the same frame of picture.
        XCTAssertEqual(trimmed.color.exposure.keyframes.first?.time, seconds(2))
        if case .number(let animatable) = trimmed.effects[0].parameters[0].value {
            XCTAssertEqual(animatable.keyframes.first?.time, seconds(2))
        } else {
            XCTFail("effect parameter lost its animation")
        }
    }

    // MARK: - Transitions need handles

    func testATransitionIsRefusedWithoutMediaToBuildItFrom() {
        var timeline = sequence([4])
        // Give the clip a known, fully-consumed source: no handles at all.
        let media = MediaRef(assetID: "bounded", name: "bounded",
                             sourceDuration: seconds(4))
        timeline.spine[0].content = .media(media)
        let id = timeline.spine[0].id

        let transition = EditTransition(duration: seconds(2))
        XCTAssertThrowsError(try timeline.addTransitionChecked(transition, to: id, edge: .tail)) { error in
            guard case MagneticEditError.insufficientHandles = error else {
                return XCTFail("expected insufficientHandles, got \(error)")
            }
        }
    }

    func testATransitionIsAllowedWhenHandlesExist() throws {
        var timeline = sequence([4])
        let media = MediaRef(assetID: "roomy", name: "roomy", sourceDuration: seconds(20))
        timeline.spine[0].content = .media(media)
        let id = timeline.spine[0].id

        try timeline.addTransitionChecked(EditTransition(duration: seconds(1)), to: id, edge: .tail)
        XCTAssertNotNil(timeline.item(id)?.transitionOut)
    }

    // MARK: - Blading connected clips

    func testAConnectedClipCanBeBladed() throws {
        var timeline = sequence([10])
        let music = try timeline.connect(clip("Score", 10, role: .music), at: .zero, lane: -2)

        let pieces = try timeline.bladeAnywhere(music.id, at: seconds(4))
        XCTAssertEqual(pieces.count, 2)

        let audio = timeline.placedItems.filter { $0.item.role.kind == .audio }
        XCTAssertEqual(audio.count, 2)
        XCTAssertEqual(audio[0].item.duration, seconds(4))
        XCTAssertEqual(audio[1].start, seconds(4))
    }

    func testALockedClipRefusesToBeBladed() throws {
        var timeline = sequence([10])
        let music = try timeline.connect(clip("Score", 10, role: .music), at: .zero, lane: -2)
        try timeline.setLocked(true, on: music.id)

        XCTAssertThrowsError(try timeline.bladeAnywhere(music.id, at: seconds(4)))
    }

    func testLaneZeroIsRejectedWithItsOwnError() {
        var timeline = sequence([4])
        XCTAssertThrowsError(try timeline.connect(clip("X", 1), at: .zero, lane: 0)) { error in
            guard case MagneticEditError.laneZeroReserved = error else {
                return XCTFail("expected laneZeroReserved, got \(error)")
            }
        }
    }

    // MARK: - Adjustment layers

    func testAnAdjustmentLayerReachesEveryClipBeneathIt() throws {
        var timeline = sequence([4, 4, 4])
        let layer = try timeline.addAdjustmentLayer(named: "Scene grade",
                                                    start: seconds(2),
                                                    duration: seconds(10),
                                                    lane: 2)
        try timeline.addEffect(EffectLibrary.filmGrain, to: layer.id)

        let affected = timeline.itemsAffected(byAdjustmentLayer: layer.id)
        // Spans 2s–12s over a 12s sequence, so it covers all three clips.
        XCTAssertEqual(affected.count, 3)

        let firstClipStack = timeline.effectiveEffects(for: timeline.spine[0].id)
        XCTAssertEqual(firstClipStack.count, 1)
        XCTAssertEqual(firstClipStack.first?.name, "Film Grain")
    }

    // MARK: - Effects

    func testEffectOrderIsPreservedAndReorderable() throws {
        var timeline = sequence([4])
        let id = timeline.spine[0].id
        try timeline.addEffect(EffectLibrary.gaussianBlur, to: id)
        try timeline.addEffect(EffectLibrary.sharpen, to: id)

        XCTAssertEqual(timeline.item(id)?.effects.map(\.name), ["Gaussian Blur", "Sharpen"])

        let sharpenID = try XCTUnwrap(timeline.item(id)?.effects[1].id)
        try timeline.moveEffect(sharpenID, on: id, to: 0)
        XCTAssertEqual(timeline.item(id)?.effects.map(\.name), ["Sharpen", "Gaussian Blur"])
    }

    func testPasteAttributesCarriesTheLookButNotTheIdentity() throws {
        var timeline = sequence([4, 4])
        let source = timeline.spine[0].id
        let target = timeline.spine[1].id

        try timeline.addEffect(EffectLibrary.vignette, to: source)
        try timeline.update(id: source) { $0.color.saturation.constant = 60 }
        try timeline.pasteAttributes(from: source, to: [target])

        XCTAssertEqual(timeline.item(target)?.color.saturation.constant, 60)
        XCTAssertEqual(timeline.item(target)?.effects.count, 1)
        // The copy must be its own effect, or toggling one would toggle both.
        XCTAssertNotEqual(timeline.item(target)?.effects[0].id,
                          timeline.item(source)?.effects[0].id)
    }

    // MARK: - Captions

    func testCaptionsExportAsSubRipWithCorrectTiming() throws {
        var timeline = sequence([10])
        _ = try timeline.addCaption("Hello there", at: seconds(1), duration: seconds(2))

        let srt = CaptionExporter.export(timeline, format: .srt)
        XCTAssertTrue(srt.contains("Hello there"))
        XCTAssertTrue(srt.contains("00:00:01,000 --> 00:00:03,000"), srt)
    }

    func testCaptionsExportAsWebVTT() throws {
        var timeline = sequence([10])
        _ = try timeline.addCaption("Line one", at: .zero, duration: seconds(2))

        let vtt = CaptionExporter.export(timeline, format: .vtt)
        XCTAssertTrue(vtt.hasPrefix("WEBVTT"))
        XCTAssertTrue(vtt.contains("00:00:00.000 --> 00:00:02.000"), vtt)
    }

    func testAnUnreadableCaptionIsFlagged() throws {
        var timeline = sequence([10])
        let words = Array(repeating: "word", count: 30).joined(separator: " ")
        _ = try timeline.addCaption(words, at: .zero, duration: seconds(2))

        let warnings = timeline.captionWarnings()
        XCTAssertEqual(warnings.count, 1)
    }

    func testCaptionsRippleWithThePicture() throws {
        var timeline = sequence([4, 4])
        let caption = try timeline.addCaption("Second shot", at: seconds(4), duration: seconds(2))
        XCTAssertEqual(timeline.placed(caption.id)?.start, seconds(4))

        // Shorten the first shot; the caption must move with what it describes.
        _ = try timeline.rippleTrim(timeline.spine[0].id, edge: .tail, by: seconds(1))
        XCTAssertEqual(timeline.placed(caption.id)?.start, seconds(3))
    }

    // MARK: - Multicam

    func testSwitchingAnglesKeepsEveryAngleAvailable() throws {
        var timeline = sequence([4, 4])
        let ids = [timeline.spine[0].id, timeline.spine[1].id]
        let multicam = try timeline.makeMulticam(from: ids, name: "Scene 4")

        let content = try XCTUnwrap(timeline.item(multicam.id)?.content.multicam)
        XCTAssertEqual(content.angles.count, 2)

        let second = content.angles[1].id
        try timeline.switchAngle(on: multicam.id, to: second, audioToo: true)

        let updated = try XCTUnwrap(timeline.item(multicam.id)?.content.multicam)
        XCTAssertEqual(updated.activeVideoAngleID, second)
        XCTAssertEqual(updated.activeAudioAngleID, second)
        XCTAssertEqual(updated.angles.count, 2, "angles must survive a switch")
    }

    // MARK: - Mixing

    func testDuckingWritesRealKeyframesUnderDialogue() throws {
        var timeline = sequence([10])
        _ = try timeline.connect(clip("Score", 10, role: .music), at: .zero, lane: -2)
        _ = try timeline.connect(clip("DX", 3, role: .dialogue), at: seconds(2), lane: -1)

        var ducking = Ducking()
        ducking.isEnabled = true
        ducking.amountDB = -12
        timeline.applyDucking(ducking)

        let score = try XCTUnwrap(timeline.placedItems.first { $0.item.name == "Score" })
        XCTAssertFalse(score.item.audio.volumeDB.keyframes.isEmpty,
                       "ducking should be visible as keyframes, not a hidden setting")
        let lowest = score.item.audio.volumeDB.keyframes.map(\.value).min() ?? 0
        XCTAssertEqual(lowest, -12, accuracy: 0.001)
    }

    func testMixCheckSpotsALevelThatWouldClip() throws {
        var timeline = sequence([10])
        for index in 0..<4 {
            var loud = clip("A\(index)", 10, role: .effects)
            loud.audio.volumeDB = AnimatableValue(0)
            _ = try timeline.connect(loud, at: .zero, lane: -(index + 1))
        }
        let check = timeline.checkMix()
        XCTAssertTrue(check.clippingRisk)
        XCTAssertGreaterThanOrEqual(check.overlappingCount, 4)
    }

    // MARK: - Smart collections

    func testASmartCollectionFiltersTheCut() throws {
        var timeline = sequence([4, 4, 4])
        try timeline.setRating(.rejected, on: timeline.spine[1].id)

        let rejected = timeline.items(matching: .rejected)
        XCTAssertEqual(rejected.count, 1)
        XCTAssertEqual(rejected.first?.item.id, timeline.spine[1].id)
    }

    func testRoleMutingReachesEveryClipWithThatRole() throws {
        var timeline = sequence([4, 4])
        _ = try timeline.connect(clip("M1", 2, role: .music), at: .zero, lane: -2)
        _ = try timeline.connect(clip("M2", 2, role: .music), at: seconds(4), lane: -2)

        timeline.setRoleEnabled(false, roleName: "Music")
        let music = timeline.placedItems.filter { $0.item.role.name == "Music" }
        XCTAssertEqual(music.count, 2)
        XCTAssertTrue(music.allSatisfy { !$0.item.isEnabled })
    }

    // MARK: - Export

    func testFcpxmlCarriesEffectsGradeAndCaptions() throws {
        var timeline = sequence([6])
        let id = timeline.spine[0].id
        try timeline.addEffect(EffectLibrary.filmGrain, to: id)
        try timeline.update(id: id) { $0.color.saturation.constant = 45 }
        _ = try timeline.addCaption("Subtitle", at: seconds(1), duration: seconds(2), language: "fr")

        let xml = FCPXMLExporter.export(timeline)

        XCTAssertTrue(xml.contains("filter-video"), xml)
        XCTAssertTrue(xml.contains("adjust-color"))
        XCTAssertTrue(xml.contains("FFFilmGrain"))
        XCTAssertTrue(xml.contains("ITT.fr"), "caption language belongs in the role")
        XCTAssertFalse(xml.contains("nan"))
    }
}
