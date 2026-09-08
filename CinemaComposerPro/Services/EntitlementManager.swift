import Foundation
import StoreKit
import SwiftUI

// MARK: - EntitlementManager
//
// Central source of truth for Pro entitlement in Cinema Composer Pro.
// Mirrors the proven SteroidOS pattern:
// - StoreKit 2, observes App Store transactions in real time.
// - Persists unlock state to UserDefaults so it survives relaunch.
// - DEBUG-only admin bypass (5-tap on version label in Setup → About),
//   gated to the developer team so it can't be abused on other accounts.
// - The Cutting Room and live runs are the Pro features.

@MainActor
final class EntitlementManager: ObservableObject {

    // MARK: - Singleton

    static let shared = EntitlementManager()

    // MARK: - Published State

    /// True when the user has Pro (via purchase, intro offer, or admin bypass).
    @Published private(set) var isPro: Bool

    /// True when Pro was unlocked via the admin bypass (not a real purchase).
    @Published private(set) var isAdminBypass: Bool = false

    /// True while the user is exploring the demo cutting room. In-memory only:
    /// never persisted, never reported to StoreKit as Pro, resets on relaunch.
    @Published private(set) var isDemoActive: Bool = false

    // MARK: - Product IDs

    enum ProductID {
        static let monthly  = "com.steroidos.cinemacomposer.pro.monthly"
        static let annual   = "com.steroidos.cinemacomposer.pro.annual"
        static let lifetime = "com.steroidos.cinemacomposer.pro.lifetime"

        static let all: Set<String> = [monthly, annual, lifetime]
        static let subscriptions: Set<String> = [monthly, annual]
    }

    // MARK: - Storage Keys

    private enum StorageKey {
        static let isPro         = "ccp.pro.unlocked"
        static let isAdminBypass = "ccp.pro.adminBypass"
    }

    // MARK: - Admin Bypass Configuration

    private static let developerTeamID = "UDM4W27W9V"
    static let adminBypassTapCount = 5
    static let adminBypassTapWindow: TimeInterval = 3.0

    // MARK: - Init

    private init() {
        let storedPro = UserDefaults.standard.object(forKey: StorageKey.isPro) as? Bool ?? false
        let storedAdmin = UserDefaults.standard.object(forKey: StorageKey.isAdminBypass) as? Bool ?? false

        // If the stored unlock was an admin bypass, re-validate that we're
        // still running on a developer-team build. If not, clear it.
        if storedAdmin && !Self.isRunningOnDeveloperTeam {
            self.isPro = false
            self.isAdminBypass = false
            UserDefaults.standard.removeObject(forKey: StorageKey.isPro)
            UserDefaults.standard.removeObject(forKey: StorageKey.isAdminBypass)
        } else {
            self.isPro = storedPro
            self.isAdminBypass = storedAdmin
        }

        Task { [weak self] in
            await self?.listenForTransactions()
            await self?.refreshEntitlements()
        }
    }

    // MARK: - Public API

    func refreshEntitlements() async {
        if isAdminBypass { return }

        var hasPro = false
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if ProductID.all.contains(transaction.productID) { hasPro = true }
            case .unverified:
                continue
            }
        }
        await MainActor.run { self.setPro(hasPro, source: .storeKit) }
    }

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                await refreshEntitlements()
            case .unverified:
                throw EntitlementError.verificationFailed
            }
        case .userCancelled:
            return
        case .pending:
            return
        @unknown default:
            throw EntitlementError.unknownPurchaseResult
        }
    }

    /// Required by App Store Review (guideline 3.1.1).
    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    func activateAdminBypass() {
        #if DEBUG
        isAdminBypass = true
        setPro(true, source: .adminBypass)
        #endif
    }

    func deactivateAdminBypass() {
        guard isAdminBypass else { return }
        isAdminBypass = false
        UserDefaults.standard.removeObject(forKey: StorageKey.isAdminBypass)
        Task { await refreshEntitlements() }
    }

    // MARK: - Demo mode

    /// Unlock the Cutting Room temporarily for the showcase demo. Deliberately
    /// NOT persisted: a relaunch lands back on the locked screen, and a
    /// StoreKit entitlement refresh during a demo never clears it.
    func activateDemo() {
        guard !isDemoActive else { return }
        isDemoActive = true
    }

    func deactivateDemo() {
        isDemoActive = false
    }

    // MARK: - Internals

    private enum EntitlementSource { case storeKit, adminBypass }

    private func setPro(_ value: Bool, source: EntitlementSource) {
        if source == .storeKit && isAdminBypass { return }
        isPro = value
        UserDefaults.standard.set(value, forKey: StorageKey.isPro)
        if source == .adminBypass {
            UserDefaults.standard.set(true, forKey: StorageKey.isAdminBypass)
        } else if !value && !isAdminBypass {
            UserDefaults.standard.removeObject(forKey: StorageKey.isAdminBypass)
        }
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            switch result {
            case .verified(let transaction):
                await transaction.finish()
                await refreshEntitlements()
            case .unverified:
                continue
            }
        }
    }

    private static var isRunningOnDeveloperTeam: Bool {
        #if !targetEnvironment(simulator)
        if let teamID = embeddedProvisioningTeamID {
            return teamID == developerTeamID
        }
        #endif
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        return bundleID.hasPrefix("com.steroidos.")
    }

    private static var embeddedProvisioningTeamID: String? {
        guard let profilePath = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: profilePath)) else { return nil }
        guard let plistStart = data.range(of: Data("<?xml".utf8)) else { return nil }
        guard let plistEnd = data.range(of: Data("</plist>".utf8), in: plistStart.upperBound..<data.count) else { return nil }
        let plistData = data.subdata(in: plistStart.lowerBound..<(plistEnd.upperBound))
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else { return nil }
        if let teamIdentifiers = plist["TeamIdentifier"] as? [String], let first = teamIdentifiers.first {
            return first
        }
        return nil
    }
}

// MARK: - Errors

enum EntitlementError: LocalizedError {
    case verificationFailed
    case unknownPurchaseResult

    var errorDescription: String? {
        switch self {
        case .verificationFailed: return "Purchase could not be verified by the App Store."
        case .unknownPurchaseResult: return "An unknown purchase result was returned."
        }
    }
}

// MARK: - View Modifier

extension View {
    /// Gate a view behind Pro. If not Pro, show the paywall.
    @ViewBuilder
    func ccpProGate<Locked: View>(
        @ViewBuilder lockedContent: () -> Locked
    ) -> some View {
        if EntitlementManager.shared.isPro {
            self
        } else {
            lockedContent()
        }
    }
}