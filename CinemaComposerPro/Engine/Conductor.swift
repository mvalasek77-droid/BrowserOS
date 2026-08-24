import Foundation

enum RunStatus: String, Equatable {
    case idle, running, completed, completedWithErrors, halted, blocked, cancelled

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .running: return "Running"
        case .completed: return "Completed"
        case .completedWithErrors: return "Completed with errors"
        case .halted: return "Halted on budget"
        case .blocked: return "Blocked"
        case .cancelled: return "Cancelled"
        }
    }
}

struct LedgerEntry: Identifiable, Equatable {
    var id: String { taskID }
    var taskID: String
    var toolID: String
    var department: Department
    var label: String
    var units: Double
    var attempts: Int
    var cost: Double
    var cumulative: Double
    var elapsed: Double
}

struct ConductorEvent: Identifiable, Equatable {
    enum Kind: Equatable { case info, success, warning, failure }

    var id = UUID()
    var at = Date()
    var kind: Kind
    var message: String
}

struct RunReport: Equatable {
    var status: RunStatus
    var dryRun: Bool
    var completed: Int
    var failures: [String]
    var spend: Double
    var estimated: Double
    var ledger: [LedgerEntry]

    var variancePercent: Double { estimated <= 0 ? 0 : (spend - estimated) / estimated * 100 }
}

/// The conductor. Walks the task graph, keeps every player inside its
/// concurrency limit, retries what is retryable — and, the part that matters to
/// a producer, stops the orchestra the moment spend outruns the budget.
@MainActor
final class Conductor: ObservableObject {
    @Published private(set) var status: RunStatus = .idle
    @Published private(set) var spend: Double = 0
    @Published private(set) var ledger: [LedgerEntry] = []
    @Published private(set) var events: [ConductorEvent] = []
    @Published private(set) var completedTaskIDs: Set<String> = []
    @Published private(set) var report: RunReport?

    private var cancelled = false
    private let maxLoggedEvents = 500

    /// Keys the plan needs that the Keychain does not have yet.
    func missingKeys(plan: ProductionPlan, registry: ToolRegistry, keys: KeychainStore) -> [String] {
        var missing: Set<String> = []
        for task in plan.tasks {
            guard let tool = registry.tool(id: task.toolID), let ref = tool.keyRef, !ref.isEmpty else { continue }
            if !keys.has(ref) { missing.insert(ref) }
        }
        return missing.sorted()
    }

    func cancel() {
        cancelled = true
        status = .cancelled
        log(.warning, "Cancelled by the producer.")
    }

    func reset() {
        cancelled = false
        spend = 0
        ledger = []
        events = []
        completedTaskIDs = []
        report = nil
        status = .idle
    }

    @discardableResult
    func run(plan: ProductionPlan,
             registry: ToolRegistry,
             keys: KeychainStore,
             dryRun: Bool = true,
             budgetCap: Double,
             maxRetries: Int = 2,
             maxConcurrency: Int = 8,
             latencyScale: Double = 0,
             failureRate: Double = 0) async -> RunReport {
        reset()
        status = .running

        let simulated = SimulatedAdapter(latencyScale: latencyScale, failureRate: failureRate)
        let live = HTTPToolAdapter()

        if !dryRun {
            let missing = missingKeys(plan: plan, registry: registry, keys: keys)
            if !missing.isEmpty {
                status = .blocked
                log(.failure, "Blocked — missing API keys: \(missing.joined(separator: ", "))")
                let blocked = RunReport(status: .blocked, dryRun: false, completed: 0,
                                        failures: ["missing keys: \(missing.joined(separator: ", "))"],
                                        spend: 0, estimated: plan.total, ledger: [])
                report = blocked
                return blocked
            }
        }

        log(.info, "Downbeat — \(plan.tasks.count) tasks, \(dryRun ? "dry run" : "LIVE"), cap \(Money.string(budgetCap)).")

        var pending = plan.tasks
        var failures: [String: String] = [:]

        while !pending.isEmpty && !cancelled && status == .running {
            // A wave is every task whose dependencies are satisfied, trimmed to
            // the global and per-tool concurrency limits.
            var perToolInWave: [String: Int] = [:]
            var wave: [PlanTask] = []
            for task in pending {
                guard wave.count < maxConcurrency else { break }
                let ready = task.dependsOn.allSatisfy { dependency in
                    completedTaskIDs.contains(dependency) || failures[dependency] != nil || !plan.tasks.contains { $0.id == dependency }
                }
                guard ready else { continue }
                if task.dependsOn.contains(where: { failures[$0] != nil }) {
                    failures[task.id] = "blocked by a failed dependency"
                    continue
                }
                let toolCap = max(1, min(registry.tool(id: task.toolID)?.limits.maxConcurrency ?? 1, maxConcurrency))
                let running = perToolInWave[task.toolID] ?? 0
                guard running < toolCap else { continue }
                perToolInWave[task.toolID] = running + 1
                wave.append(task)
            }

            let handled = Set(wave.map(\.id)).union(failures.keys)
            pending.removeAll { handled.contains($0.id) }

            if wave.isEmpty {
                for task in pending { failures[task.id] = "blocked by a failed dependency" }
                pending = []
                break
            }

            // Budget guardrail: check before spending, not after.
            var admitted: [PlanTask] = []
            var projected = spend
            for task in wave {
                if projected + task.cost > budgetCap {
                    status = .halted
                    log(.failure, "Halted at \(task.id): \(Money.string(projected + task.cost)) would exceed the \(Money.string(budgetCap)) cap.")
                    break
                }
                projected += task.cost
                admitted.append(task)
            }
            guard !admitted.isEmpty else { break }

            let outcomes = await withTaskGroup(of: TaskOutcome.self) { group -> [TaskOutcome] in
                for task in admitted {
                    guard let tool = registry.tool(id: task.toolID) else {
                        group.addTask { TaskOutcome(task: task, attempts: 1, elapsed: 0,
                                                    failure: ToolInvocationError.notCallable(task.toolID).localizedDescription) }
                        continue
                    }
                    let apiKey: String? = {
                        guard !dryRun, let ref = tool.keyRef, !ref.isEmpty else { return nil }
                        return keys.secret(for: ref)
                    }()
                    let adapter: ToolAdapter = (dryRun || !tool.canCallLive) ? simulated : live
                    self.log(.info, "▸ \(task.id) → \(task.toolID) · \(Units.count(task.units)) \(task.unitLabel) · \(Money.string(task.cost))")
                    group.addTask {
                        await Self.perform(task: task, tool: tool, adapter: adapter, apiKey: apiKey, maxRetries: maxRetries)
                    }
                }
                var collected: [TaskOutcome] = []
                for await outcome in group { collected.append(outcome) }
                return collected
            }

            for outcome in outcomes.sorted(by: { $0.task.id < $1.task.id }) {
                let task = outcome.task
                if let failure = outcome.failure {
                    failures[task.id] = failure
                    log(.failure, "✗ \(task.id): \(failure)")
                    continue
                }
                // Retried attempts still burn money upstream — charge for each.
                let cost = task.cost * Double(outcome.attempts)
                spend += cost
                completedTaskIDs.insert(task.id)
                ledger.append(LedgerEntry(taskID: task.id, toolID: task.toolID, department: task.department,
                                          label: task.label, units: task.units, attempts: outcome.attempts,
                                          cost: cost, cumulative: spend, elapsed: outcome.elapsed))
                log(.success, "✓ \(task.id) \(Money.string(cost)) · running \(Money.string(spend))")
            }
        }

        if status == .running {
            status = failures.isEmpty ? .completed : .completedWithErrors
        }
        let finished = RunReport(status: status, dryRun: dryRun, completed: completedTaskIDs.count,
                                 failures: failures.map { "\($0.key): \($0.value)" }.sorted(),
                                 spend: spend, estimated: plan.total, ledger: ledger)
        report = finished
        log(finished.status == .completed ? .success : .warning,
            "\(finished.status.label) — spent \(Money.string(finished.spend)) of \(Money.string(finished.estimated)) estimated.")
        return finished
    }

    /// One task, with retries. Nonisolated so a whole wave can run concurrently.
    private nonisolated static func perform(task: PlanTask,
                                            tool: AITool,
                                            adapter: ToolAdapter,
                                            apiKey: String?,
                                            maxRetries: Int) async -> TaskOutcome {
        let startedAt = Date()
        var attempt = 0
        var lastFailure = ToolInvocationError.transport("\(task.id) never ran").localizedDescription
        while attempt <= maxRetries {
            attempt += 1
            do {
                _ = try await adapter.invoke(tool: tool, task: task, apiKey: apiKey, attempt: attempt)
                return TaskOutcome(task: task, attempts: attempt, elapsed: Date().timeIntervalSince(startedAt), failure: nil)
            } catch {
                lastFailure = error.localizedDescription
                let retryable = (error as? ToolInvocationError)?.isRetryable ?? false
                if !retryable || attempt > maxRetries { break }
                let backoff = min(pow(2, Double(attempt)) * 0.05, 1.0)
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            }
        }
        return TaskOutcome(task: task, attempts: attempt, elapsed: Date().timeIntervalSince(startedAt), failure: lastFailure)
    }

    /// Sendable by construction — the failure crosses back as text, not as an
    /// arbitrary Error, so a wave can run concurrently without qualification.
    private struct TaskOutcome: Sendable {
        var task: PlanTask
        var attempts: Int
        var elapsed: Double
        var failure: String?
    }

    private func log(_ kind: ConductorEvent.Kind, _ message: String) {
        events.append(ConductorEvent(kind: kind, message: message))
        if events.count > maxLoggedEvents { events.removeFirst(events.count - maxLoggedEvents) }
    }
}
