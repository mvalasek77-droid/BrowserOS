import Foundation

/// The rack. Everything the conductor can call lives here, versioned, so a new
/// model or a whole new vendor arrives as data rather than as a new build.
@MainActor
final class ToolRegistry: ObservableObject {
    @Published private(set) var tools: [AITool]
    private var history: [String: [AITool]] = [:]

    init(tools: [AITool] = ToolCatalog.builtIn) {
        self.tools = tools.map {
            var tool = $0
            tool.registeredAt = tool.registeredAt ?? Date()
            return tool
        }
    }

    enum RegistryError: LocalizedError {
        case invalid(String, [String])
        case duplicate(String)
        case unknown(String)
        case noHistory(String)

        var errorDescription: String? {
            switch self {
            case .invalid(let id, let problems): return "\(id) is not a valid tool: \(problems.joined(separator: "; "))"
            case .duplicate(let id): return "\(id) is already on the rack — upgrade it instead"
            case .unknown(let id): return "no tool called \(id)"
            case .noHistory(let id): return "no previous version of \(id) to roll back to"
            }
        }
    }

    enum InstallOutcome: Equatable {
        case added(String)
        case upgraded(id: String, from: String, to: String)
        case skipped(id: String, reason: String)

        var summary: String {
            switch self {
            case .added(let id): return "added \(id)"
            case .upgraded(let id, let from, let to): return "\(id) \(from) → \(to)"
            case .skipped(let id, let reason): return "\(id) skipped — \(reason)"
            }
        }
    }

    // MARK: - Reading

    func tool(id: String) -> AITool? { tools.first { $0.id == id } }

    func previousVersions(of id: String) -> [AITool] { history[id] ?? [] }

    /// Every distinct API key the rack can consume.
    var keyRefs: [String] {
        Array(Set(tools.compactMap { $0.keyRef })).sorted()
    }

    /// Candidates for a job, best quality first.
    func candidates(capability: String,
                    tier: ProductionTier? = nil,
                    availableKeys: Set<String>? = nil,
                    includeExperimental: Bool = false) -> [AITool] {
        tools.candidates(capability: capability, tier: tier, availableKeys: availableKeys, includeExperimental: includeExperimental)
    }

    // MARK: - Writing

    @discardableResult
    func register(_ tool: AITool) throws -> AITool {
        let problems = tool.validationErrors()
        guard problems.isEmpty else { throw RegistryError.invalid(tool.id, problems) }
        guard self.tool(id: tool.id) == nil else { throw RegistryError.duplicate(tool.id) }
        var stored = tool
        stored.registeredAt = Date()
        tools.append(stored)
        return stored
    }

    /// Install a newer build of something already on the rack. Downgrades are
    /// refused unless forced, so a stale pack cannot silently roll a rate back.
    @discardableResult
    func upgrade(_ tool: AITool, force: Bool = false) throws -> InstallOutcome {
        guard let current = self.tool(id: tool.id) else {
            try register(tool)
            return .added(tool.id)
        }
        let problems = tool.validationErrors()
        guard problems.isEmpty else { throw RegistryError.invalid(tool.id, problems) }

        guard let incoming = SemanticVersion(tool.version), let existing = SemanticVersion(current.version) else {
            throw RegistryError.invalid(tool.id, ["unreadable version"])
        }
        if !force {
            if incoming == existing { return .skipped(id: tool.id, reason: "already at \(current.version)") }
            if incoming < existing { return .skipped(id: tool.id, reason: "refusing downgrade \(current.version) → \(tool.version)") }
        }
        history[tool.id, default: []].append(current)
        var stored = tool
        stored.registeredAt = Date()
        if let index = tools.firstIndex(where: { $0.id == tool.id }) { tools[index] = stored }
        return .upgraded(id: tool.id, from: current.version, to: tool.version)
    }

    /// The escape hatch when a shiny new model turns out to be worse.
    @discardableResult
    func rollback(id: String) throws -> AITool {
        guard var stack = history[id], let previous = stack.popLast() else { throw RegistryError.noHistory(id) }
        history[id] = stack
        guard let index = tools.firstIndex(where: { $0.id == id }) else { throw RegistryError.unknown(id) }
        tools[index] = previous
        return previous
    }

    func remove(id: String) {
        tools.removeAll { $0.id == id }
        history[id] = nil
    }

    /// Edit a rate in place — the thing you do the morning a vendor changes pricing.
    func updatePricing(id: String, rate: Double) throws {
        guard let index = tools.firstIndex(where: { $0.id == id }) else { throw RegistryError.unknown(id) }
        tools[index].pricing.rate = max(0, rate)
        tools[index].ratesAsOf = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
    }

    @discardableResult
    func install(pack: ToolPack) -> [InstallOutcome] {
        pack.tools.compactMap { tool in
            do { return try upgrade(tool) } catch { return .skipped(id: tool.id, reason: error.localizedDescription) }
        }
    }

    func install(packData: Data) throws -> [InstallOutcome] {
        let pack = try JSONDecoder().decode(ToolPack.self, from: packData)
        return install(pack: pack)
    }

    func exportPack(name: String = "cinema-composer-pro-rack") throws -> Data {
        let pack = ToolPack(name: name, version: "1.0.0", description: "Exported from Cinema Composer Pro", tools: tools)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(pack)
    }
}


extension Array where Element == AITool {
    /// The one place candidate filtering lives, so the rack and the planner can
    /// never disagree about what is callable.
    func candidates(capability: String,
                    tier: ProductionTier? = nil,
                    availableKeys: Set<String>? = nil,
                    includeExperimental: Bool = false) -> [AITool] {
        filter { $0.capabilities.contains(capability) }
            .filter { tool in
                guard let tier else { return true }
                return tool.tiers.contains(tier)
            }
            .filter { includeExperimental || $0.status == .stable }
            .filter { tool in
                guard let availableKeys else { return true }   // planning without a vault assumes keys exist
                guard let ref = tool.keyRef, !ref.isEmpty else { return true }
                return availableKeys.contains(ref)
            }
            .sorted { $0.quality > $1.quality }
    }
}
