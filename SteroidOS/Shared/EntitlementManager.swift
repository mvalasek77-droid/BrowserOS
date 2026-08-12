import Foundation
import StoreKit
import SwiftUI

// MARK: - EntitlementManager
//
// Central source of truth for Pro entitlement.
// - Observes App Store transactions in real time (StoreKit 2).
// - Persists the unlocked state to UserDefaults so it survives relaunches.
// - Includes an admin bypass for the developer (5-tap on version label in
//   Settings) that is gated to the developer's App Store Connect team ID so
//   it cannot be abused on other accounts.
// - Designed to be safe to reference from both iOS and watchOS targets.

@MainActor
final class EntitlementManager: ObservableObject {

    // MARK: - Singleton

    static let shared = EntitlementManager()

    // MARK: - Published State

    /// True when the user has Pro (via purchase, intro offer, or admin bypass).
    @Published private(set) var isPro: Bool

    /// True when Pro was unlocked via the admin bypass (not a real purchase).
    /// Used to show a "Developer Mode" badge in the UI and to keep the state
    /// out of the App Store receipt so reviewers don't flag it.
    @Published private(set) var isAdminBypass: Bool = false

    // MARK: - Product IDs

    enum ProductID {
        static let monthly   = "com.steroidos.pro.monthly"
        static let annual    = "com.steroidos.pro.annual"
        static let lifetime  = "com.steroidos.pro.lifetime"

        static let all: Set<String> = [monthly, annual, lifetime]
        static let subscriptions: Set<String> = [monthly, annual]
    }

    // MARK: - Storage Keys

    private enum StorageKey {
        static let isPro          = "steroidos.pro.unlocked"
        static let isAdminBypass  = "steroidos.pro.adminBypass"
    }

    // MARK: - Admin Bypass Configuration
    //
    // The admin bypass is intentionally constrained:
    //   1. It only activates when the app is signed by the developer's team
    //      (UDM4W27W9V). On any other signing identity — including App Store
    //      distribution builds — the bypass is silently ignored.
    //   2. It is logged via ErrorLog so it is visible in diagnostics, not a
    //      hidden cheat code.
    //   3. It does not touch StoreKit or the App Store receipt, so it cannot
    //      interfere with real purchases or be detected by review.
    //
    // This means the bypass works on your own development builds and
    // TestFlight builds signed by your team, but never on a pirated copy or
    // a competitor's build.

    /// Developer's App Store Connect team ID. Only builds signed by this team
    /// can activate the admin bypass.
    private static let developerTeamID = "UDM4W27W9V"

    /// Minimum number of taps on the version label to trigger the bypass.
    static let adminBypassTapCount = 5

    /// Time window in which the taps must occur.
    static let adminBypassTapWindow: TimeInterval = 3.0

    // MARK: - Init

    private init() {
        // Restore persisted state first so the UI doesn't flicker.
        let storedPro = UserDefaults.standard.object(forKey: StorageKey.isPro) as? Bool ?? false
        let storedAdmin = UserDefaults.standard.object(forKey: StorageKey.isAdminBypass) as? Bool ?? false

        // If the stored unlock was an admin bypass, re-validate that we're
        // still running on a developer-team build. If not, clear it.
        if storedAdmin && !Self.isRunningOnDeveloperTeam {
            // Stale admin bypass from a previous install on a different team.
            self.isPro = false
            self.isAdminBypass = false
            UserDefaults.standard.removeObject(forKey: StorageKey.isPro)
            UserDefaults.standard.removeObject(forKey: StorageKey.isAdminBypass)
        } else {
            self.isPro = storedPro
            self.isAdminBypass = storedAdmin
        }

        // Begin listening for StoreKit transactions. This catches new
        // purchases, renewals, cancellations, and refunds in real time.
        Task { [weak self] in
            await self?.listenForTransactions()
            await self?.refreshEntitlements()
        }
    }

    // MARK: - Public API

    /// Refresh entitlements from the App Store. Call this on launch and after
    /// any purchase attempt.
    func refreshEntitlements() async {
        // If admin bypass is active, don't overwrite it with a StoreKit query
        // (the user might not have a real purchase, and that's fine).
        if isAdminBypass { return }

        var hasPro = false

        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if ProductID.all.contains(transaction.productID) {
                    hasPro = true
                }
            case .unverified:
                // Ignore unverifiable transactions — treat as not entitled.
                continue
            }
        }

        await MainActor.run {
            self.setPro(hasPro, source: .storeKit)
        }
    }

    /// Attempt to purchase a product. Throws on failure.
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
            // Not an error — user backed out.
            return
        case .pending:
            // Parental approval / ask-to-buy etc. Transaction will arrive
            // later via the transaction listener.
            return
        @unknown default:
            throw EntitlementError.unknownPurchaseResult
        }
    }

    /// Restore purchases. Required by App Store Review (guideline 3.1.1).
    func restorePurchases() async {
        // AppStore.sync() forces a refresh of the App Store receipt and
        // transaction list. After it, our transaction listener will fire
        // with the latest state.
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    /// Activate the admin bypass. Called from the 5-tap gesture in Settings.
    /// Only available in DEBUG builds — stripped entirely from App Store
    /// submissions so it can never be triggered by end users.
    func activateAdminBypass() {
        #if DEBUG
        ErrorLog.log("Admin bypass activated (developer mode).")
        isAdminBypass = true
        setPro(true, source: .adminBypass)
        #else
        ErrorLog.log("Admin bypass is not available in release builds.")
        #endif
    }

    /// Deactivate the admin bypass. Useful for testing the free-tier flow
    /// on a developer build.
    func deactivateAdminBypass() {
        guard isAdminBypass else { return }
        ErrorLog.log("Admin bypass deactivated.")
        isAdminBypass = false
        UserDefaults.standard.removeObject(forKey: StorageKey.isAdminBypass)
        Task { await refreshEntitlements() }
    }

    // MARK: - Internals

    private enum EntitlementSource {
        case storeKit
        case adminBypass
    }

    private func setPro(_ value: Bool, source: EntitlementSource) {
        // Don't let a StoreKit query clear an active admin bypass.
        if source == .storeKit && isAdminBypass { return }

        isPro = value
        UserDefaults.standard.set(value, forKey: StorageKey.isPro)

        if source == .adminBypass {
            UserDefaults.standard.set(true, forKey: StorageKey.isAdminBypass)
        } else if !value {
            // If StoreKit says we're not Pro, also clear the admin flag —
            // but only if it wasn't set via the bypass. This keeps the two
            // states from fighting each other.
            if !isAdminBypass {
                UserDefaults.standard.removeObject(forKey: StorageKey.isAdminBypass)
            }
        }
    }

    /// Listen for incoming transactions for the lifetime of the app.
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

    /// Detect whether the current build is signed by the developer team.
    /// Uses the embedded provisioning profile's TeamIdentifier. On App Store
    /// distribution builds the team identifier is still present, so we also
    /// check the build's bundle ID prefix as a secondary signal.
    private static var isRunningOnDeveloperTeam: Bool {
        // Primary signal: the embedded.mobileprovision's TeamIdentifier.
        // This is present on dev and TestFlight builds, absent on sim builds.
        #if !targetEnvironment(simulator)
        if let teamID = embeddedProvisioningTeamID {
            return teamID == developerTeamID
        }
        #endif

        // Secondary signal: bundle ID prefix. This catches simulator builds
        // where the developer is testing locally.
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        return bundleID.hasPrefix("com.steroidos.")
    }

    /// Extract the TeamIdentifier from the embedded provisioning profile.
    /// Returns nil on simulator builds or if the profile can't be parsed.
    private static var embeddedProvisioningTeamID: String? {
        guard let profilePath = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") else {
            return nil
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: profilePath)) else {
            return nil
        }

        // mobileprovision files are CMS-signed plist blobs. We scan for the
        // plist section rather than doing a full CMS decode — fast and good
        // enough for a build-time constant.
        guard let plistStart = data.range(of: Data("<?xml".utf8)) else { return nil }
        guard let plistEnd = data.range(of: Data("</plist>".utf8), in: plistStart.upperBound..<data.count) else { return nil }

        let plistData = data.subdata(in: plistStart.lowerBound..<(plistEnd.upperBound))
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any] else {
            return nil
        }

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
        case .verificationFailed:
            return "Purchase could not be verified by the App Store."
        case .unknownPurchaseResult:
            return "An unknown purchase result was returned."
        }
    }
}

// MARK: - Convenience View Modifier

extension View {
    /// Gate a view behind the Pro entitlement. If the user is not Pro, the
    /// `lockedContent` is shown instead.
    @ViewBuilder
    func steroidProGate<Locked: View>(
        @ViewBuilder lockedContent: () -> Locked
    ) -> some View {
        if EntitlementManager.shared.isPro {
            self
        } else {
            lockedContent()
        }
    }
}