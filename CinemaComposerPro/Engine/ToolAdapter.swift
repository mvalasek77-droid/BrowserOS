import Foundation

struct ToolInvocationResult: Equatable {
    var toolID: String
    var taskID: String
    var units: Double
    var simulated: Bool
    var summary: String
}

enum ToolInvocationError: LocalizedError {
    case missingKey(String)
    case notCallable(String)
    case http(status: Int, body: String)
    case transport(String)

    var isRetryable: Bool {
        switch self {
        case .http(let status, _): return status == 429 || status >= 500
        case .transport: return true
        case .missingKey, .notCallable: return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .missingKey(let ref): return "Add the \(ref) API key in Keys before running live."
        case .notCallable(let id): return "\(id) has no endpoint configured — it can only run simulated."
        case .http(let status, let body): return "HTTP \(status): \(body)"
        case .transport(let message): return message
        }
    }
}

protocol ToolAdapter {
    /// `attempt` is 1-based; adapters that behave differently on a retry (the
    /// simulator, notably) need to know which try this is.
    func invoke(tool: AITool, task: PlanTask, apiKey: String?, attempt: Int) async throws -> ToolInvocationResult
}

/// Deterministic stand-in used for dry runs, budgeting and tests. It bills
/// exactly what the plan predicted, which is what makes a dry run auditable.
struct SimulatedAdapter: ToolAdapter {
    var latencyScale: Double = 0        // 0 = instant, 1 = real generation time
    var failureRate: Double = 0
    var seed: UInt64 = 7

    func invoke(tool: AITool, task: PlanTask, apiKey: String?, attempt: Int) async throws -> ToolInvocationResult {
        if latencyScale > 0 {
            let seconds = min(task.workerSeconds * latencyScale, 2.0)
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
        // Simulated failures hit the first attempt only, so a retry can succeed
        // the way a real transient failure does.
        if failureRate > 0, attempt == 1 {
            var rng = SeededGenerator(seed: seed &+ UInt64(task.id.djb2Hash % 100_000))
            if Double.random(in: 0...1, using: &rng) < failureRate {
                throw ToolInvocationError.transport("\(tool.id): upstream generation failed (simulated)")
            }
        }
        return ToolInvocationResult(toolID: tool.id, taskID: task.id, units: task.units, simulated: true,
                                    summary: "\(Units.count(task.units)) \(task.unitLabel)")
    }
}

/// Generic live adapter, driven entirely by tool-pack data: endpoint, method,
/// header template, body template. Adding a vendor never means editing code.
/// Placeholders {{apiKey}}, {{units}}, {{prompt}}, {{taskId}} are filled here.
struct HTTPToolAdapter: ToolAdapter {
    var session: URLSession = .shared
    var timeout: TimeInterval = 120

    func invoke(tool: AITool, task: PlanTask, apiKey: String?, attempt: Int = 1) async throws -> ToolInvocationResult {
        guard let endpoint = tool.endpoint, let url = URL(string: fill(endpoint, tool: tool, task: task, apiKey: apiKey)) else {
            throw ToolInvocationError.notCallable(tool.id)
        }
        if tool.requiresKey, (apiKey ?? "").isEmpty {
            throw ToolInvocationError.missingKey(tool.keyRef ?? tool.vendor)
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = tool.method ?? "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (header, value) in tool.headers ?? [:] {
            request.setValue(fill(value, tool: tool, task: task, apiKey: apiKey), forHTTPHeaderField: header)
        }
        if request.httpMethod != "GET" {
            let raw = (tool.body ?? ["prompt": "{{prompt}}", "duration_seconds": "{{units}}"])
                .mapValues { fill($0, tool: tool, task: task, apiKey: apiKey) }
            let typed: [String: Any] = raw.mapValues { value in
                if let number = Double(value), !value.contains(" ") { return number }
                return value
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: typed)
        }

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                let body = String(data: data.prefix(400), encoding: .utf8) ?? ""
                throw ToolInvocationError.http(status: status, body: redacting(body, apiKey: apiKey))
            }
            return ToolInvocationResult(toolID: tool.id, taskID: task.id, units: task.units, simulated: false,
                                        summary: "\(data.count) bytes returned")
        } catch let error as ToolInvocationError {
            throw error
        } catch {
            throw ToolInvocationError.transport(redacting(error.localizedDescription, apiKey: apiKey))
        }
    }

    private func fill(_ template: String, tool: AITool, task: PlanTask, apiKey: String?) -> String {
        template
            .replacingOccurrences(of: "{{apiKey}}", with: apiKey ?? "")
            .replacingOccurrences(of: "{{units}}", with: String(format: "%.2f", task.units))
            .replacingOccurrences(of: "{{taskId}}", with: task.id)
            .replacingOccurrences(of: "{{prompt}}", with: task.prompt ?? task.label)
    }

    private func redacting(_ text: String, apiKey: String?) -> String {
        guard let apiKey, apiKey.count >= 8 else { return text }
        return text.replacingOccurrences(of: apiKey, with: KeychainStore.mask(apiKey))
    }
}
