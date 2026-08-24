import Foundation

/// A feature that extends the producer's budget without touching the engine.
///
/// iOS cannot load code at runtime, so extensibility here comes in two forms:
/// tool packs (JSON, new vendors and models) and modules (compiled-in features
/// the operator switches on). Both mean the app grows without the core changing.
protocol BudgetModule {
    var id: String { get }
    var name: String { get }
    var summary: String { get }
    var isEnabledByDefault: Bool { get }

    func extend(budget: Budget, breakdown: Breakdown) -> Budget
}

extension BudgetModule {
    var isEnabledByDefault: Bool { false }

    /// Recompute the roll-ups after a module appends line items — modules should
    /// never have to know how contingency or unit economics are derived.
    func rebuilding(_ budget: Budget, with additions: [BudgetLineItem]) -> Budget {
        var updated = budget
        updated.lineItems.append(contentsOf: additions)
        updated.subtotal = updated.lineItems.reduce(0) { $0 + $1.subtotal }
        updated.contingency = updated.subtotal * (updated.contingencyPercent / 100)
        updated.total = updated.subtotal + updated.contingency

        updated.departments = Department.allCases.compactMap { department in
            let items = updated.lineItems.filter { $0.department == department }
            guard !items.isEmpty else { return nil }
            let amount = items.reduce(0) { $0 + $1.subtotal }
            return DepartmentTotal(department: department, subtotal: amount, itemCount: items.count,
                                   sharePercent: updated.subtotal <= 0 ? 0 : amount / updated.subtotal * 100)
        }.sorted { $0.subtotal > $1.subtotal }

        let supervision = updated.lineItems.first { $0.id == "human.supervision" }?.subtotal ?? 0
        updated.unitEconomics = UnitEconomics(
            perRuntimeMinute: updated.runtimeMinutes <= 0 ? 0 : updated.total / updated.runtimeMinutes,
            perFinishedSecond: updated.spec.runtimeSeconds <= 0 ? 0 : updated.total / updated.spec.runtimeSeconds,
            perShot: updated.shotCount == 0 ? 0 : updated.total / Double(updated.shotCount),
            perScene: updated.sceneCount == 0 ? 0 : updated.total / Double(updated.sceneCount),
            aiSharePercent: updated.total <= 0 ? 0 : updated.aiSubtotal / updated.total * 100,
            humanSharePercent: updated.total <= 0 ? 0 : supervision / updated.total * 100
        )
        return updated
    }
}

/// Festival and distribution deliverables — the costs that appear the day after
/// picture lock and are missing from every AI cost calculator.
struct FestivalDeliveryModule: BudgetModule {
    let id = "festival-delivery"
    let name = "Festival & delivery"
    let summary = "DCP mastering, captions, localization and festival entry fees."

    var festivalEntries: Int = 8
    var localizationLanguages: Int = 2
    var dcpPerMinute: Double = 12
    var captionsPerMinute: Double = 2.5
    var localizationPerLanguage: Double = 180
    var festivalEntryFee: Double = 65

    func extend(budget: Budget, breakdown: Breakdown) -> Budget {
        let minutes = budget.runtimeMinutes
        let additions: [BudgetLineItem] = [
            BudgetLineItem(id: "delivery.dcp", department: .distribution, label: "DCP mastering & QC",
                           toolName: "Festival & delivery module", toolID: id, pricingModel: "per_minute",
                           unitLabel: "runtime minutes", units: minutes, billableUnits: minutes,
                           unitRate: dcpPerMinute, subtotal: minutes * dcpPerMinute, note: nil),
            BudgetLineItem(id: "delivery.captions", department: .distribution, label: "Captions & subtitles (source language)",
                           toolName: "Festival & delivery module", toolID: id, pricingModel: "per_minute",
                           unitLabel: "runtime minutes", units: minutes, billableUnits: minutes,
                           unitRate: captionsPerMinute, subtotal: minutes * captionsPerMinute, note: nil),
            BudgetLineItem(id: "delivery.localization", department: .distribution, label: "Localization × \(localizationLanguages)",
                           toolName: "Festival & delivery module", toolID: id, pricingModel: "flat",
                           unitLabel: "languages", units: Double(localizationLanguages), billableUnits: Double(localizationLanguages),
                           unitRate: localizationPerLanguage, subtotal: Double(localizationLanguages) * localizationPerLanguage, note: nil),
            BudgetLineItem(id: "delivery.festivals", department: .distribution, label: "Festival entry fees × \(festivalEntries)",
                           toolName: "Festival & delivery module", toolID: id, pricingModel: "flat",
                           unitLabel: "entries", units: Double(festivalEntries), billableUnits: Double(festivalEntries),
                           unitRate: festivalEntryFee, subtotal: Double(festivalEntries) * festivalEntryFee, note: nil),
        ]
        return rebuilding(budget, with: additions)
    }
}

/// The other thing nobody budgets: selling the picture once it exists.
struct MarketingPackageModule: BudgetModule {
    let id = "marketing-package"
    let name = "Marketing package"
    let summary = "Trailer, teaser, key art and a social cutdown pack, priced off the same rack."

    var socialCutdowns: Int = 12
    var keyArtVariants: Int = 6

    func extend(budget: Budget, breakdown: Breakdown) -> Budget {
        // Priced from what the picture itself costs per second, so it tracks
        // the tier and strategy instead of being a made-up flat fee.
        let perSecond = budget.unitEconomics.perFinishedSecond
        let trailerSeconds: Double = 150
        let teaserSeconds: Double = 45
        let cutdownSeconds = Double(socialCutdowns) * 20
        let keyArtCost = Double(keyArtVariants) * 4.5

        let additions: [BudgetLineItem] = [
            BudgetLineItem(id: "marketing.trailer", department: .distribution, label: "Trailer (2:30)",
                           toolName: "Marketing module", toolID: id, pricingModel: "derived",
                           unitLabel: "seconds", units: trailerSeconds, billableUnits: trailerSeconds,
                           unitRate: perSecond, subtotal: trailerSeconds * perSecond, note: "priced at the picture's own per-second cost"),
            BudgetLineItem(id: "marketing.teaser", department: .distribution, label: "Teaser (0:45)",
                           toolName: "Marketing module", toolID: id, pricingModel: "derived",
                           unitLabel: "seconds", units: teaserSeconds, billableUnits: teaserSeconds,
                           unitRate: perSecond, subtotal: teaserSeconds * perSecond, note: nil),
            BudgetLineItem(id: "marketing.social", department: .distribution, label: "Social cutdowns × \(socialCutdowns)",
                           toolName: "Marketing module", toolID: id, pricingModel: "derived",
                           unitLabel: "seconds", units: cutdownSeconds, billableUnits: cutdownSeconds,
                           unitRate: perSecond, subtotal: cutdownSeconds * perSecond, note: nil),
            BudgetLineItem(id: "marketing.keyart", department: .distribution, label: "Key art × \(keyArtVariants)",
                           toolName: "Marketing module", toolID: id, pricingModel: "per_image",
                           unitLabel: "images", units: Double(keyArtVariants), billableUnits: Double(keyArtVariants),
                           unitRate: 4.5, subtotal: keyArtCost, note: nil),
        ]
        return rebuilding(budget, with: additions)
    }
}

/// Which modules are switched on. Persisted, so the producer's choices survive
/// a relaunch the way the rest of the project does.
@MainActor
final class ModuleRegistry: ObservableObject {
    @Published var enabledIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(enabledIDs), forKey: Self.defaultsKey) }
    }

    private static let defaultsKey = "ccp.enabledModules"
    let modules: [BudgetModule]

    init(modules: [BudgetModule] = [FestivalDeliveryModule(), MarketingPackageModule()]) {
        self.modules = modules
        if let stored = UserDefaults.standard.array(forKey: Self.defaultsKey) as? [String] {
            enabledIDs = Set(stored)
        } else {
            enabledIDs = Set(modules.filter(\.isEnabledByDefault).map(\.id))
        }
    }

    func isEnabled(_ module: BudgetModule) -> Bool { enabledIDs.contains(module.id) }

    func setEnabled(_ module: BudgetModule, _ enabled: Bool) {
        if enabled { enabledIDs.insert(module.id) } else { enabledIDs.remove(module.id) }
    }

    /// Run every enabled module over a freshly built budget.
    func apply(to budget: Budget, breakdown: Breakdown) -> Budget {
        modules.filter { enabledIDs.contains($0.id) }
            .reduce(budget) { $1.extend(budget: $0, breakdown: breakdown) }
    }
}
