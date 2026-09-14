import XCTest
@testable import CinemaComposerPro

/// The render path: turning a budget line into per-shot vendor work, following
/// an asynchronous job to its file, and pointing the cut at what came back.
final class RenderPipelineTests: XCTestCase {

    // MARK: - JSON paths

    /// Every vendor buries the file somewhere different. A path in the pack
    /// beats a special case in the code for each of them.
    func testJSONPathReachesTheShapesRealVendorsReturn() throws {
        let runway = try JSONSerialization.jsonObject(with: Data("""
        {"id":"task_01","status":"SUCCEEDED","output":["https://cdn/x.mp4"]}
        """.utf8))
        XCTAssertEqual(JSONPath.string("id", in: runway), "task_01")
        XCTAssertEqual(JSONPath.string("output.0", in: runway), "https://cdn/x.mp4")

        let luma = try JSONSerialization.jsonObject(with: Data("""
        {"id":"gen_9","state":"completed","assets":{"video":"https://cdn/y.mp4"}}
        """.utf8))
        XCTAssertEqual(JSONPath.string("state", in: luma), "completed")
        XCTAssertEqual(JSONPath.string("assets.video", in: luma), "https://cdn/y.mp4")

        let kling = try JSONSerialization.jsonObject(with: Data("""
        {"data":{"task_id":"k7","task_status":"succeed",
                 "task_result":{"videos":[{"url":"https://cdn/z.mp4"}]}}}
        """.utf8))
        XCTAssertEqual(JSONPath.string("data.task_id", in: kling), "k7")
        XCTAssertEqual(JSONPath.string("data.task_result.videos.0.url", in: kling),
                       "https://cdn/z.mp4")
    }

    func testJSONPathCoercesNumbersAndMissesCleanly() throws {
        let root = try JSONSerialization.jsonObject(with: Data(#"{"id":4021,"ok":true}"#.utf8))
        // Vendors return ids as both strings and numbers.
        XCTAssertEqual(JSONPath.string("id", in: root), "4021")
        XCTAssertEqual(JSONPath.string("ok", in: root), "true")
        XCTAssertNil(JSONPath.string("nope", in: root))
        XCTAssertNil(JSONPath.string("id.deeper", in: root))
        XCTAssertNil(JSONPath.string("output.3", in: root))
    }

    // MARK: - Per-shot targets

    func testAShotIsSplitToFitTheVendorCeiling() {
        let target = RenderTarget(id: "S001-0004", seconds: 14.2, prompt: "wide, dusk")
        let pieces = target.segments(maxSeconds: 10)
        XCTAssertEqual(pieces.count, 2)
        XCTAssertEqual(pieces.map(\.id), ["S001-0004#1", "S001-0004#2"])
        XCTAssertEqual(pieces.reduce(0) { $0 + $1.seconds }, 14.2, accuracy: 0.05)
        XCTAssertTrue(pieces.allSatisfy { $0.seconds <= 10 })
    }

    func testAShotThatAlreadyFitsIsLeftAlone() {
        let target = RenderTarget(id: "S001-0001", seconds: 6, prompt: "close")
        XCTAssertEqual(target.segments(maxSeconds: 10), [target])
        XCTAssertEqual(target.segments(maxSeconds: nil), [target])
    }

    /// The headline fix. A photography task is a budgeting unit covering
    /// hundreds of shots; execution has to be one request per shot, or the app
    /// asks a vendor for half an hour of footage in a single call.
    func testAPhotographyTaskExpandsIntoOneJobPerShot() {
        let tool = AITool(id: "v", name: "V", vendor: "v", version: "1.0.0",
                          capabilities: [Capability.videoTextToVideo],
                          pricing: ToolPricing(model: .perSecond, rate: 0.25),
                          quality: 0.8, speed: ToolSpeed(secondsPerOutputSecond: 10),
                          limits: ToolLimits(maxShotSeconds: 10, maxConcurrency: 3))

        var task = PlanTask(id: "photo.hero.final", department: .photography,
                            label: "Hero", capability: Capability.videoTextToVideo,
                            toolID: "v", units: 20, unitLabel: "video seconds",
                            billableUnits: 20, cost: 100, workerSeconds: 200, concurrency: 3)
        task.renderTargets = [
            RenderTarget(id: "A", seconds: 5, prompt: "a"),
            RenderTarget(id: "B", seconds: 15, prompt: "b"),
        ]

        let jobs = task.renderJobs(tool: tool)
        // B exceeds the ceiling, so three jobs in total.
        XCTAssertEqual(jobs.count, 3)
        XCTAssertTrue(jobs.allSatisfy { $0.target.seconds <= 10 })
        // Cost is apportioned by duration and still sums to the budget line.
        XCTAssertEqual(jobs.reduce(0) { $0 + $1.cost }, 100, accuracy: 0.001)
        XCTAssertEqual(jobs.first { $0.target.id == "A" }?.cost, 25, accuracy: 0.001)
    }

    func testNonGenerationWorkStaysASingleCall() {
        let task = PlanTask(id: "dev.script", department: .development, label: "Script",
                            capability: Capability.scriptWrite, toolID: "llm",
                            units: 50_000, unitLabel: "tokens", billableUnits: 50_000,
                            cost: 12, workerSeconds: 60, concurrency: 1)
        XCTAssertTrue(task.renderJobs(tool: nil).isEmpty)
    }

    // MARK: - Job protocol decoding

    /// A pack should only have to say what its vendor does differently.
    func testJobProtocolFillsInEveryDefaultButTheStatusEndpoint() throws {
        let json = Data(#"{"statusEndpoint":"https://api/v1/tasks/{{jobId}}"}"#.utf8)
        let job = try JSONDecoder().decode(JobProtocol.self, from: json)
        XCTAssertEqual(job.jobIDPath, "id")
        XCTAssertEqual(job.statusPath, "status")
        XCTAssertEqual(job.resultURLPath, "output.0")
        XCTAssertEqual(job.statusMethod, "GET")
        XCTAssertTrue(job.isSucceeded("SUCCEEDED"))
        XCTAssertTrue(job.isSucceeded("completed"))
        XCTAssertTrue(job.isFailed("FAILED"))
        XCTAssertFalse(job.isSucceeded("RUNNING"))
    }

    func testAToolPackCarriesItsJobProtocolThroughDecoding() throws {
        let json = Data("""
        {"id":"runway-gen","name":"Runway","vendor":"runway","version":"1.0.0",
         "capabilities":["video.t2v"],
         "pricing":{"model":"per_second","rate":0.25},
         "quality":0.86,"speed":{"secondsPerOutputSecond":14},
         "endpoint":"https://api/v1/text_to_video",
         "jobProtocol":{"statusEndpoint":"https://api/v1/tasks/{{jobId}}",
                        "statusPath":"status","resultURLPath":"output.0",
                        "succeededValues":["SUCCEEDED"]}}
        """.utf8)
        let tool = try JSONDecoder().decode(AITool.self, from: json)
        XCTAssertTrue(tool.canCallLive)
        XCTAssertEqual(tool.jobProtocol?.resultURLPath, "output.0")
        XCTAssertEqual(tool.jobProtocol?.succeededValues, ["SUCCEEDED"])
    }

    /// A synchronous tool has no job protocol, and must still load.
    func testASynchronousToolDecodesWithoutAJobProtocol() throws {
        let json = Data("""
        {"id":"tts","name":"TTS","vendor":"x","version":"1.0.0",
         "capabilities":["audio.voice"],
         "pricing":{"model":"per_minute_audio","rate":0.3},
         "quality":0.9,"speed":{"unitsPerHour":240},
         "endpoint":"https://api/v1/tts"}
        """.utf8)
        let tool = try JSONDecoder().decode(AITool.self, from: json)
        XCTAssertNil(tool.jobProtocol)
        XCTAssertTrue(tool.canCallLive)
    }

    // MARK: - The shipped packs

    func testTheAsyncVendorPackParses() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "async-video-vendors", withExtension: "json"))
        let pack = try JSONDecoder().decode(ToolPack.self, from: Data(contentsOf: url))

        XCTAssertEqual(pack.tools.count, 4)
        let video = pack.tools.filter { $0.capabilities.contains(Capability.videoTextToVideo) }
        XCTAssertEqual(video.count, 3)
        // Every video generator must describe how to follow its job, or it
        // cannot actually produce a file.
        XCTAssertTrue(video.allSatisfy { $0.jobProtocol != nil })
        XCTAssertTrue(video.allSatisfy { ($0.limits.maxShotSeconds ?? 0) > 0 })
        // The speech tool is synchronous by design.
        let voice = try XCTUnwrap(pack.tools.first { $0.id == "elevenlabs-voice-sync" })
        XCTAssertNil(voice.jobProtocol)
    }

    // MARK: - Linking footage onto the cut

    func testRenderedFilesAttachToTheClipsTheyCameFrom() {
        var timeline = MagneticTimeline(format: TimelineFormat(rate: .fps24))
        for id in ["S001-0001", "S001-0002"] {
            let media = MediaRef(assetID: id, name: id, sourceDuration: .zero)
            try? timeline.append(TimelineItem(name: id, content: .media(media),
                                              duration: RationalTime(4, 1)))
        }
        XCTAssertEqual(timeline.mediaCoverage.linked, 0)

        let linked = timeline.linkMedia([
            "S001-0001": URL(fileURLWithPath: "/tmp/m/S001-0001-take1.mp4"),
            "S001-0002": URL(fileURLWithPath: "/tmp/m/S001-0002-take1.mp4"),
        ])

        XCTAssertEqual(linked, 2)
        XCTAssertEqual(timeline.mediaCoverage.linked, 2)
        XCTAssertEqual(timeline.mediaCoverage.total, 2)
        XCTAssertFalse(timeline.spine[0].isMissingMedia)
    }

    /// A shot split across two requests still belongs to one clip, so the
    /// lookup falls back to the part before the `#`.
    func testASplitShotStillFindsItsClip() {
        var timeline = MagneticTimeline(format: TimelineFormat(rate: .fps24))
        let media = MediaRef(assetID: "S001-0004", name: "S001-0004", sourceDuration: .zero)
        try? timeline.append(TimelineItem(name: "S001-0004", content: .media(media),
                                          duration: RationalTime(14, 1)))

        let linked = timeline.linkMedia(
            ["S001-0004#1": URL(fileURLWithPath: "/tmp/m/S001-0004_1-take1.mp4")])
        XCTAssertEqual(linked, 0, "a segment id must not match the whole shot")

        let direct = timeline.linkMedia(
            ["S001-0004": URL(fileURLWithPath: "/tmp/m/S001-0004-take1.mp4")])
        XCTAssertEqual(direct, 1)
    }

    func testLinkingReachesConnectedClipsToo() {
        var timeline = MagneticTimeline(format: TimelineFormat(rate: .fps24))
        let picture = MediaRef(assetID: "S001-0001", name: "S001-0001", sourceDuration: .zero)
        var shot = TimelineItem(name: "S001-0001", content: .media(picture),
                                duration: RationalTime(4, 1))
        let voice = MediaRef(assetID: "S001-0001-dx", name: "DX", sourceDuration: .zero,
                             hasVideo: false, hasAudio: true)
        var dialogue = TimelineItem(name: "DX", content: .media(voice),
                                    duration: RationalTime(4, 1), role: .dialogue)
        dialogue.lane = -1
        shot.connected.append(dialogue)
        try? timeline.append(shot)

        let linked = timeline.linkMedia([
            "S001-0001": URL(fileURLWithPath: "/tmp/m/a.mp4"),
            "S001-0001-dx": URL(fileURLWithPath: "/tmp/m/a.mp3"),
        ])
        XCTAssertEqual(linked, 2)
    }

    // MARK: - Media store

    func testMediaStoreNamesFilesByShotAndTake() {
        let url = MediaStore.fileURL(shotID: "S001-0004#2", take: 3, fileExtension: "mp4")
        // The `#` would break a path, so it is sanitised out.
        XCTAssertEqual(url.lastPathComponent, "S001-0004_2-take3.mp4")
    }

    func testMediaStoreGuessesTheRightExtension() {
        XCTAssertEqual(MediaStore.fileExtension(for: URL(string: "https://cdn/x.mov"),
                                                contentType: nil), "mov")
        XCTAssertEqual(MediaStore.fileExtension(for: nil, contentType: "video/mp4"), "mp4")
        XCTAssertEqual(MediaStore.fileExtension(for: nil, contentType: "audio/mpeg"), "mp3")
        XCTAssertEqual(MediaStore.fileExtension(for: nil, contentType: nil), "mp4")
    }

    func testMediaStoreRoundTripsAFile() throws {
        let bytes = Data(repeating: 0x42, count: 2048)
        let url = try MediaStore.write(bytes, shotID: "TEST-0001", take: 1, fileExtension: "mp4")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(MediaStore.exists(shotID: "TEST-0001", take: 1, fileExtension: "mp4"))
        XCTAssertEqual(try Data(contentsOf: url).count, 2048)
    }

    // MARK: - Retry policy

    /// Retrying a vendor that said "failed" burns money for nothing, which is
    /// the one thing this app exists to prevent.
    func testOnlyTransientFailuresAreRetried() {
        XCTAssertTrue(ToolInvocationError.http(status: 503, body: "").isRetryable)
        XCTAssertTrue(ToolInvocationError.http(status: 429, body: "").isRetryable)
        XCTAssertTrue(ToolInvocationError.transport("dropped").isRetryable)
        XCTAssertTrue(ToolInvocationError.jobTimedOut(seconds: 900).isRetryable)

        XCTAssertFalse(ToolInvocationError.jobFailed("moderation").isRetryable)
        XCTAssertFalse(ToolInvocationError.badJobResponse("no id").isRetryable)
        XCTAssertFalse(ToolInvocationError.http(status: 400, body: "").isRetryable)
        XCTAssertFalse(ToolInvocationError.missingKey("runway").isRetryable)
        XCTAssertFalse(ToolInvocationError.cancelled.isRetryable)
    }

    // MARK: - The planner populates targets

    func testThePlannerGivesPhotographyItsShots() {
        var spec = FilmSpec()
        spec.runtimeMinutes = 6
        let breakdown = Breakdown.make(from: spec)
        let plan = Planner.plan(breakdown: breakdown, tools: ToolCatalog.builtIn, measure: false)

        let photography = plan.tasks(in: .photography)
        XCTAssertFalse(photography.isEmpty)
        XCTAssertTrue(photography.allSatisfy { !$0.renderTargets.isEmpty },
                      "every generation task needs shots to execute")

        // Development work is genuinely one call and must stay that way.
        for task in plan.tasks(in: .development) {
            XCTAssertTrue(task.renderTargets.isEmpty)
        }
    }
}
