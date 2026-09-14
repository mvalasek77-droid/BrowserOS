import Foundation

struct ToolInvocationResult: Equatable {
    var toolID: String
    var taskID: String
    var units: Double
    var simulated: Bool
    var summary: String
    /// Which shot this produced, when the work was a generation.
    var targetID: String?
    /// Where the vendor put the file.
    var remoteURL: URL?
    /// Where it landed on this device. This is what the timeline points at.
    var localURL: URL?
    var bytes: Int = 0

    init(toolID: String,
         taskID: String,
         units: Double,
         simulated: Bool,
         summary: String,
         targetID: String? = nil,
         remoteURL: URL? = nil,
         localURL: URL? = nil,
         bytes: Int = 0) {
        self.toolID = toolID
        self.taskID = taskID
        self.units = units
        self.simulated = simulated
        self.summary = summary
        self.targetID = targetID
        self.remoteURL = remoteURL
        self.localURL = localURL
        self.bytes = bytes
    }
}

enum ToolInvocationError: LocalizedError {
    case missingKey(String)
    case notCallable(String)
    case http(status: Int, body: String)
    case transport(String)
    case badJobResponse(String)
    case jobFailed(String)
    case jobTimedOut(seconds: Double)
    case cancelled

    var isRetryable: Bool {
        switch self {
        case .http(let status, _): return status == 429 || status >= 500
        case .transport, .jobTimedOut: return true
        // A vendor that says "failed" will say it again. Retrying burns money
        // for nothing, which is the one thing this app exists to prevent.
        case .missingKey, .notCallable, .badJobResponse, .jobFailed, .cancelled: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingKey(let ref): return "Add the \(ref) API key in Keys before running live."
        case .notCallable(let id): return "\(id) has no endpoint configured — it can only run simulated."
        case .http(let status, let body): return "HTTP \(status): \(body)"
        case .transport(let message): return message
        case .badJobResponse(let detail): return "The vendor's reply did not match the tool pack: \(detail)"
        case .jobFailed(let detail): return "The vendor reported the job failed: \(detail)"
        case .jobTimedOut(let seconds): return "Gave up after \(Int(seconds))s waiting for the vendor."
        case .cancelled: return "Cancelled."
        }
    }
}

protocol ToolAdapter: Sendable {
    /// `target` is the individual shot being generated, or nil for work that is
    /// not per-shot — a script pass, a QC sweep. `attempt` is 1-based; adapters
    /// that behave differently on a retry need to know which try this is.
    func invoke(tool: AITool,
                task: PlanTask,
                target: RenderTarget?,
                apiKey: String?,
                attempt: Int) async throws -> ToolInvocationResult
}

/// Deterministic stand-in used for dry runs, budgeting and tests. It bills
/// exactly what the plan predicted, which is what makes a dry run auditable.
struct SimulatedAdapter: ToolAdapter {
    var latencyScale: Double = 0        // 0 = instant, 1 = real generation time
    var failureRate: Double = 0
    var seed: UInt64 = 7

    func invoke(tool: AITool,
                task: PlanTask,
                target: RenderTarget?,
                apiKey: String?,
                attempt: Int) async throws -> ToolInvocationResult {
        let units = target?.seconds ?? task.units
        if latencyScale > 0 {
            let seconds = min(tool.estimatedSeconds(units: units) * latencyScale, 2.0)
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
        // Simulated failures hit the first attempt only, so a retry can succeed
        // the way a real transient failure does.
        if failureRate > 0, attempt == 1 {
            let key = target?.id ?? task.id
            var rng = SeededGenerator(seed: seed &+ UInt64(key.djb2Hash % 100_000))
            if Double.random(in: 0...1, using: &rng) < failureRate {
                throw ToolInvocationError.transport("\(tool.id): upstream generation failed (simulated)")
            }
        }
        return ToolInvocationResult(
            toolID: tool.id, taskID: task.id, units: units, simulated: true,
            summary: target.map { "\($0.id) · \(Units.count($0.seconds))s simulated" }
                ?? "\(Units.count(units)) \(task.unitLabel)",
            targetID: target?.id)
    }
}

/// The live adapter, driven entirely by tool-pack data.
///
/// Real generators are asynchronous: the POST returns a job id, the job runs
/// for a minute or ten, and only then is there a file. So this submits, polls
/// until the vendor says it is done, reads the result URL out of the reply and
/// downloads it into the media store. A pack with no `jobProtocol` is treated
/// as synchronous, which is right for speech APIs that return audio inline.
struct HTTPToolAdapter: ToolAdapter {
    var session: URLSession = .shared
    var timeout: TimeInterval = 120
    /// Overridable so tests can poll without waiting on wall-clock seconds.
    var pollScale: Double = 1

    func invoke(tool: AITool,
                task: PlanTask,
                target: RenderTarget?,
                apiKey: String?,
                attempt: Int) async throws -> ToolInvocationResult {
        guard tool.canCallLive else { throw ToolInvocationError.notCallable(tool.id) }
        if tool.requiresKey, (apiKey ?? "").isEmpty {
            throw ToolInvocationError.missingKey(tool.keyRef ?? tool.vendor)
        }

        let units = target?.seconds ?? task.units
        let submitted = try await submit(tool: tool, task: task, target: target,
                                         units: units, apiKey: apiKey)

        // Synchronous vendor: the bytes are already here.
        guard let job = tool.jobProtocol else {
            return try store(data: submitted.data,
                             contentType: submitted.contentType,
                             remoteURL: nil,
                             tool: tool, task: task, target: target, units: units)
        }

        let jobID = try jobIdentifier(from: submitted.data, protocol: job)
        let resultURL = try await poll(jobID: jobID, tool: tool, task: task,
                                       target: target, units: units,
                                       apiKey: apiKey, protocol: job)
        return try await download(from: resultURL, tool: tool, task: task,
                                  target: target, units: units, apiKey: apiKey)
    }

    // MARK: - Submit

    private struct Submitted {
        var data: Data
        var contentType: String?
    }

    private func submit(tool: AITool,
                        task: PlanTask,
                        target: RenderTarget?,
                        units: Double,
                        apiKey: String?) async throws -> Submitted {
        guard let endpoint = tool.endpoint,
              let url = URL(string: fill(endpoint, tool: tool, task: task,
                                         target: target, units: units, apiKey: apiKey))
        else { throw ToolInvocationError.notCallable(tool.id) }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = tool.method ?? "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (header, value) in tool.headers ?? [:] {
            request.setValue(fill(value, tool: tool, task: task, target: target,
                                  units: units, apiKey: apiKey),
                             forHTTPHeaderField: header)
        }
        if request.httpMethod != "GET" {
            let raw = (tool.body ?? ["prompt": "{{prompt}}", "duration_seconds": "{{units}}"])
                .mapValues { fill($0, tool: tool, task: task, target: target,
                                  units: units, apiKey: apiKey) }
            request.httpBody = try JSONSerialization.data(withJSONObject: typed(raw))
        }

        let (data, response) = try await send(request, apiKey: apiKey)
        return Submitted(data: data,
                         contentType: (response as? HTTPURLResponse)?
                             .value(forHTTPHeaderField: "Content-Type"))
    }

    // MARK: - Poll

    private func jobIdentifier(from data: Data, protocol job: JobProtocol) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "unreadable"
            throw ToolInvocationError.badJobResponse("submit reply was not JSON — \(preview)")
        }
        guard let identifier = JSONPath.string(job.jobIDPath, in: root), !identifier.isEmpty else {
            throw ToolInvocationError.badJobResponse("no job id at \"\(job.jobIDPath)\"")
        }
        return identifier
    }

    private func poll(jobID: String,
                      tool: AITool,
                      task: PlanTask,
                      target: RenderTarget?,
                      units: Double,
                      apiKey: String?,
                      protocol job: JobProtocol) async throws -> URL {
        let deadline = Date().addingTimeInterval(job.timeoutSeconds)
        let interval = max(0.05, job.pollSeconds * pollScale)

        while Date() < deadline {
            if Task.isCancelled { throw ToolInvocationError.cancelled }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            if Task.isCancelled { throw ToolInvocationError.cancelled }

            let filled = fill(job.statusEndpoint, tool: tool, task: task, target: target,
                              units: units, apiKey: apiKey)
                .replacingOccurrences(of: "{{jobId}}", with: jobID)
            guard let url = URL(string: filled) else {
                throw ToolInvocationError.badJobResponse("status endpoint is not a URL: \(filled)")
            }

            var request = URLRequest(url: url, timeoutInterval: timeout)
            request.httpMethod = job.statusMethod
            for (header, value) in tool.headers ?? [:] {
                request.setValue(fill(value, tool: tool, task: task, target: target,
                                      units: units, apiKey: apiKey),
                                 forHTTPHeaderField: header)
            }

            let (data, _) = try await send(request, apiKey: apiKey)
            guard let root = try? JSONSerialization.jsonObject(with: data) else {
                throw ToolInvocationError.badJobResponse("status reply was not JSON")
            }
            guard let state = JSONPath.string(job.statusPath, in: root) else {
                throw ToolInvocationError.badJobResponse("no status at \"\(job.statusPath)\"")
            }

            if job.isFailed(state) {
                let detail = job.failureMessagePath
                    .flatMap { JSONPath.string($0, in: root) } ?? state
                throw ToolInvocationError.jobFailed(redacting(detail, apiKey: apiKey))
            }
            guard job.isSucceeded(state) else { continue }   // still running

            guard let text = JSONPath.string(job.resultURLPath, in: root),
                  let resultURL = URL(string: text) else {
                throw ToolInvocationError.badJobResponse(
                    "job finished but no file at \"\(job.resultURLPath)\"")
            }
            return resultURL
        }
        throw ToolInvocationError.jobTimedOut(seconds: job.timeoutSeconds)
    }

    // MARK: - Download

    private func download(from url: URL,
                          tool: AITool,
                          task: PlanTask,
                          target: RenderTarget?,
                          units: Double,
                          apiKey: String?) async throws -> ToolInvocationResult {
        var request = URLRequest(url: url, timeoutInterval: max(timeout, 300))
        // Result URLs are usually pre-signed and reject an auth header, so only
        // send one when the vendor serves the file from its own API host.
        if url.host == URL(string: tool.endpoint ?? "")?.host {
            for (header, value) in tool.headers ?? [:] {
                request.setValue(fill(value, tool: tool, task: task, target: target,
                                      units: units, apiKey: apiKey),
                                 forHTTPHeaderField: header)
            }
        }

        do {
            let (temporary, response) = try await session.download(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                throw ToolInvocationError.http(status: status, body: "downloading \(url.lastPathComponent)")
            }
            let contentType = (response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Content-Type")
            let bytes = (try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let ext = MediaStore.fileExtension(for: url, contentType: contentType)

            let local = try MediaStore.adopt(temporaryFile: temporary,
                                             shotID: target?.id ?? task.id,
                                             take: target?.take ?? 1,
                                             suggestedExtension: ext)
            return ToolInvocationResult(
                toolID: tool.id, taskID: task.id, units: units, simulated: false,
                summary: "\(target?.id ?? task.id) · \(byteLabel(bytes)) downloaded",
                targetID: target?.id, remoteURL: url, localURL: local, bytes: bytes)
        } catch let error as ToolInvocationError {
            throw error
        } catch {
            throw ToolInvocationError.transport(redacting(error.localizedDescription, apiKey: apiKey))
        }
    }

    /// A synchronous vendor handed the bytes back directly.
    private func store(data: Data,
                       contentType: String?,
                       remoteURL: URL?,
                       tool: AITool,
                       task: PlanTask,
                       target: RenderTarget?,
                       units: Double) throws -> ToolInvocationResult {
        let ext = MediaStore.fileExtension(for: remoteURL, contentType: contentType)
        // A JSON reply from a synchronous tool is an answer, not media — a
        // script pass or a QC verdict. Only keep something that is actually a file.
        let looksLikeMedia = !(contentType?.lowercased().contains("json") ?? false)
        var local: URL?
        if looksLikeMedia, !data.isEmpty {
            local = try MediaStore.write(data,
                                         shotID: target?.id ?? task.id,
                                         take: target?.take ?? 1,
                                         fileExtension: ext)
        }
        return ToolInvocationResult(
            toolID: tool.id, taskID: task.id, units: units, simulated: false,
            summary: local == nil
                ? "\(byteLabel(data.count)) returned"
                : "\(target?.id ?? task.id) · \(byteLabel(data.count)) saved",
            targetID: target?.id, remoteURL: remoteURL, localURL: local, bytes: data.count)
    }

    // MARK: - Plumbing

    private func send(_ request: URLRequest, apiKey: String?) async throws -> (Data, URLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                let body = String(data: data.prefix(400), encoding: .utf8) ?? ""
                throw ToolInvocationError.http(status: status, body: redacting(body, apiKey: apiKey))
            }
            return (data, response)
        } catch let error as ToolInvocationError {
            throw error
        } catch {
            throw ToolInvocationError.transport(redacting(error.localizedDescription, apiKey: apiKey))
        }
    }

    /// Values that parse as numbers are sent as JSON numbers, since vendors
    /// reject `"duration_seconds": "5.00"` where they wanted `5`.
    private func typed(_ raw: [String: String]) -> [String: Any] {
        raw.mapValues { value in
            if let number = Double(value), !value.contains(" ") { return number }
            return value
        }
    }

    /// `{{units}}` and `{{prompt}}` resolve to the *shot* when there is one, so
    /// a request asks for one clip instead of a whole department's footage.
    private func fill(_ template: String,
                      tool: AITool,
                      task: PlanTask,
                      target: RenderTarget?,
                      units: Double,
                      apiKey: String?) -> String {
        template
            .replacingOccurrences(of: "{{apiKey}}", with: apiKey ?? "")
            .replacingOccurrences(of: "{{units}}", with: String(format: "%.2f", units))
            .replacingOccurrences(of: "{{seconds}}", with: String(format: "%.2f", units))
            .replacingOccurrences(of: "{{taskId}}", with: task.id)
            .replacingOccurrences(of: "{{shotId}}", with: target?.id ?? task.id)
            .replacingOccurrences(of: "{{take}}", with: String(target?.take ?? 1))
            .replacingOccurrences(of: "{{prompt}}", with: target?.prompt ?? task.prompt ?? task.label)
    }

    private func byteLabel(_ bytes: Int) -> String {
        bytes > 1_000_000
            ? String(format: "%.1f MB", Double(bytes) / 1_000_000)
            : "\(bytes) bytes"
    }

    private func redacting(_ text: String, apiKey: String?) -> String {
        guard let apiKey, apiKey.count >= 8 else { return text }
        return text.replacingOccurrences(of: apiKey, with: KeychainStore.mask(apiKey))
    }
}
