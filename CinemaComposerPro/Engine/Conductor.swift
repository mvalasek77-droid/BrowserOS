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

    /// Footage this run produced, keyed by shot id. The cutting room links
    /// these onto the timeline so a clip points at a real file rather than at
    /// a promise.
    @Published private(set) var renders: [String: URL] = [:]

    var renderedShotCount: Int { renders.count }

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

    /// Generate one shot on one vendor, outside a full run.
    ///
    /// This is what an audition needs: the same shot put to several generators
    /// so an editor can look at them side by side and keep the best. It reuses
    /// the same adapter as a run, so a take comes back as a real file with a
    /// real price rather than an estimate.
    func renderTake(shotID: String,
                    seconds: Double,
                    prompt: String,
                    tool: AITool,
                    keys: KeychainStore,
                    dryRun: Bool,
                    takeIndex: Int,
                    maxRetries: Int = 1) async -> Result<RenderOutput, Error> {
        let task = PlanTask(id: "take.\(shotID)",
                            department: .photography,
                            label: "Take \(takeIndex) · \(shotID)",
                            capability: Capability.videoTextToVideo,
                            toolID: tool.id,
                            units: seconds,
                            unitLabel: "video seconds",
                            billableUnits: tool.billableUnits(for: seconds),
                            cost: tool.estimatedCost(units: seconds),
                            workerSeconds: tool.estimatedSeconds(units: seconds),
                            concurrency: 1,
                            prompt: prompt)
        let target = RenderTarget(id: shotID, seconds: seconds, prompt: prompt, take: takeIndex)

        let useSimulator = dryRun || !tool.canCallLive
        let adapter: ToolAdapter = useSimulator ? SimulatedAdapter() : HTTPToolAdapter()
        let apiKey: String? = {
            guard !useSimulator, let ref = tool.keyRef, !ref.isEmpty else { return nil }
            return keys.secret(for: ref)
        }()

        log(.info, "▸ take \(takeIndex) of \(shotID) → \(tool.name) · \(Money.string(task.cost))")

        var attempt = 0
        var lastError: Error = ToolInvocationError.transport("never ran")
        while attempt <= maxRetries {
            attempt += 1
            do {
                let result = try await adapter.invoke(tool: tool, task: task, target: target,
                                                      apiKey: apiKey, attempt: attempt)
                spend += task.cost
                if let local = result.localURL { renders[shotID] = local }
                log(.success, "✓ take \(takeIndex) of \(shotID) on \(tool.name) · \(Money.string(task.cost))")
                return .success(RenderOutput(targetID: shotID,
                                             remoteURL: result.remoteURL,
                                             localURL: result.localURL,
                                             bytes: result.bytes,
                                             simulated: result.simulated))
            } catch {
                lastError = error
                let retryable = (error as? ToolInvocationError)?.isRetryable ?? false
                if !retryable || attempt > maxRetries { break }
            }
        }
        log(.failure, "✗ take \(takeIndex) of \(shotID) on \(tool.name): \(lastError.localizedDescription)")
        return .failure(lastError)
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
        renders = [:]
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
                    let jobCount = task.renderJobs(tool: tool).count
                    let scope = jobCount > 1 ? " · \(jobCount) shots" : ""
                    self.log(.info, "▸ \(task.id) → \(task.toolID) · \(Units.count(task.units)) \(task.unitLabel)\(scope) · \(Money.string(task.cost))")
                    group.addTask {
                        await Self.perform(task: task, tool: tool, adapter: adapter,
                                           apiKey: apiKey, maxRetries: maxRetries,
                                           maxConcurrency: maxConcurrency)
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
                // Charge for what actually came back, retries included.
                let cost = outcome.cost
                spend += cost
                completedTaskIDs.insert(task.id)
                ledger.append(LedgerEntry(taskID: task.id, toolID: task.toolID, department: task.department,
                                          label: task.label, units: task.units, attempts: outcome.attempts,
                                          cost: cost, cumulative: spend, elapsed: outcome.elapsed))

                // Keep every file the run produced, keyed by shot.
                for render in outcome.renders where render.localURL != nil {
                    renders[render.targetID] = render.localURL
                }

                if let partial = outcome.partialFailure {
                    log(.warning, "⚠ \(task.id) \(outcome.completedJobs)/\(outcome.totalJobs) shots — \(partial)")
                } else if outcome.totalJobs > 1 {
                    log(.success, "✓ \(task.id) \(outcome.completedJobs) shots · \(Money.string(cost)) · running \(Money.string(spend))")
                } else {
                    log(.success, "✓ \(task.id) \(Money.string(cost)) · running \(Money.string(spend))")
                }
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

    /// One task. Nonisolated so a whole wave can run concurrently.
    ///
    /// A generation task is not one call — it is one call per shot. The task is
    /// expanded into its render jobs here and they run under the vendor's own
    /// concurrency limit, so a bucket of 332 hero shots becomes 332 requests of
    /// a few seconds each rather than one impossible request for half an hour
    /// of footage.
    private nonisolated static func perform(task: PlanTask,
                                            tool: AITool,
                                            adapter: ToolAdapter,
                                            apiKey: String?,
                                            maxRetries: Int,
                                            maxConcurrency: Int) async -> TaskOutcome {
        let startedAt = Date()
        let jobs = task.renderJobs(tool: tool)

        // Work that genuinely is a single call — a script pass, a QC sweep.
        guard !jobs.isEmpty else {
            let attempt = await attemptOne(task: task, tool: tool, target: nil,
                                           adapter: adapter, apiKey: apiKey, maxRetries: maxRetries)
            return TaskOutcome(task: task,
                               attempts: attempt.attempts,
                               elapsed: Date().timeIntervalSince(startedAt),
                               failure: attempt.failure,
                               cost: attempt.failure == nil ? task.cost * Double(attempt.attempts) : 0,
                               renders: attempt.output.map { [$0] } ?? [],
                               completedJobs: attempt.failure == nil ? 1 : 0,
                               totalJobs: 1)
        }

        let lanes = max(1, min(tool.limits.maxConcurrency, maxConcurrency))
        var completed = 0
        var attempts = 0
        var cost = 0.0
        var renders: [RenderOutput] = []
        var failures: [String] = []

        // Slide a window of `lanes` jobs so the vendor is never over-driven.
        var index = 0
        while index < jobs.count {
            if Task.isCancelled { break }
            let slice = jobs[index..<min(index + lanes, jobs.count)]
            index += lanes

            let batch = await withTaskGroup(of: JobOutcome.self) { group -> [JobOutcome] in
                for job in slice {
                    group.addTask {
                        var outcome = await attemptOne(task: task, tool: tool, target: job.target,
                                                       adapter: adapter, apiKey: apiKey,
                                                       maxRetries: maxRetries)
                        outcome.cost = job.cost
                        return outcome
                    }
                }
                var collected: [JobOutcome] = []
                for await outcome in group { collected.append(outcome) }
                return collected
            }

            for outcome in batch {
                attempts += outcome.attempts
                if let failure = outcome.failure {
                    failures.append(failure)
                } else {
                    completed += 1
                    // Retried attempts still burn money upstream.
                    cost += outcome.cost * Double(outcome.attempts)
                    if let output = outcome.output { renders.append(output) }
                }
            }
        }

        // A task that produced some of its shots is a partial, not a failure —
        // report it as such and charge only for what actually came back.
        var summary: String?
        if !failures.isEmpty {
            let first = failures[0]
            summary = failures.count == 1
                ? first
                : "\(failures.count) of \(jobs.count) shots failed — first: \(first)"
        }
        return TaskOutcome(task: task,
                           attempts: max(1, attempts),
                           elapsed: Date().timeIntervalSince(startedAt),
                           failure: completed == 0 ? summary : nil,
                           partialFailure: completed > 0 ? summary : nil,
                           cost: cost,
                           renders: renders,
                           completedJobs: completed,
                           totalJobs: jobs.count)
    }

    /// One invocation with retries and backoff.
    private nonisolated static func attemptOne(task: PlanTask,
                                               tool: AITool,
                                               target: RenderTarget?,
                                               adapter: ToolAdapter,
                                               apiKey: String?,
                                               maxRetries: Int) async -> JobOutcome {
        var attempt = 0
        var lastFailure = ToolInvocationError.transport("\(task.id) never ran").localizedDescription
        while attempt <= maxRetries {
            attempt += 1
            do {
                let result = try await adapter.invoke(tool: tool, task: task, target: target,
                                                      apiKey: apiKey, attempt: attempt)
                let output = RenderOutput(targetID: result.targetID ?? task.id,
                                          remoteURL: result.remoteURL,
                                          localURL: result.localURL,
                                          bytes: result.bytes,
                                          simulated: result.simulated)
                return JobOutcome(attempts: attempt, failure: nil, output: output, cost: 0)
            } catch {
                lastFailure = error.localizedDescription
                let retryable = (error as? ToolInvocationError)?.isRetryable ?? false
                if !retryable || attempt > maxRetries { break }
                let backoff = min(pow(2, Double(attempt)) * 0.05, 1.0)
                try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
            }
        }
        let label = target.map { "\($0.id): " } ?? ""
        return JobOutcome(attempts: attempt, failure: label + lastFailure, output: nil, cost: 0)
    }

    private struct JobOutcome: Sendable {
        var attempts: Int
        var failure: String?
        var output: RenderOutput?
        var cost: Double
    }

    /// Sendable by construction — the failure crosses back as text, not as an
    /// arbitrary Error, so a wave can run concurrently without qualification.
    private struct TaskOutcome: Sendable {
        var task: PlanTask
        var attempts: Int
        var elapsed: Double
        var failure: String?
        var partialFailure: String?
        var cost: Double
        var renders: [RenderOutput]
        var completedJobs: Int
        var totalJobs: Int

        init(task: PlanTask, attempts: Int, elapsed: Double, failure: String?,
             partialFailure: String? = nil, cost: Double = 0,
             renders: [RenderOutput] = [], completedJobs: Int = 0, totalJobs: Int = 1) {
            self.task = task
            self.attempts = attempts
            self.elapsed = elapsed
            self.failure = failure
            self.partialFailure = partialFailure
            self.cost = cost
            self.renders = renders
            self.completedJobs = completedJobs
            self.totalJobs = totalJobs
        }
    }

    private func log(_ kind: ConductorEvent.Kind, _ message: String) {
        events.append(ConductorEvent(kind: kind, message: message))
        if events.count > maxLoggedEvents { events.removeFirst(events.count - maxLoggedEvents) }
    }
}
