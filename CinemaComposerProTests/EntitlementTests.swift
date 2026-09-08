import XCTest
@testable import CinemaComposerPro

/// The Cutting Room is the Pro feature. These tests pin the contract: the
/// gate flips with the entitlement, the bypass toggles cleanly, and the
/// product IDs in the StoreKit config match what the manager looks for.
@MainActor
final class EntitlementTests: XCTestCase {

    override func setUp() async throws {
        // Start every test from a clean slate.
        UserDefaults.standard.removeObject(forKey: "ccp.pro.unlocked")
        UserDefaults.standard.removeObject(forKey: "ccp.pro.adminBypass")
    }

    override func tearDown() async throws {
        if EntitlementManager.shared.isAdminBypass {
            EntitlementManager.shared.deactivateAdminBypass()
        }
        UserDefaults.standard.removeObject(forKey: "ccp.pro.unlocked")
        UserDefaults.standard.removeObject(forKey: "ccp.pro.adminBypass")
    }

    func testAdminBypassUnlocksAndLocksCleanly() {
        XCTAssertFalse(EntitlementManager.shared.isPro)
        EntitlementManager.shared.activateAdminBypass()
        // DEBUG builds: the bypass works. Release builds: no-op.
        #if DEBUG
        XCTAssertTrue(EntitlementManager.shared.isPro)
        XCTAssertTrue(EntitlementManager.shared.isAdminBypass)
        #else
        XCTAssertFalse(EntitlementManager.shared.isPro)
        #endif

        EntitlementManager.shared.deactivateAdminBypass()
        XCTAssertFalse(EntitlementManager.shared.isAdminBypass)
    }

    func testBypassSurvivesRelaunch() {
        EntitlementManager.shared.activateAdminBypass()
        // A "relaunch": re-reading persisted state. The singleton re-inits in
        // process, so simulate what init does with the same keys.
        #if DEBUG
        let storedPro = UserDefaults.standard.object(forKey: "ccp.pro.unlocked") as? Bool ?? false
        let storedAdmin = UserDefaults.standard.object(forKey: "ccp.pro.adminBypass") as? Bool ?? false
        XCTAssertTrue(storedPro, "bypass should persist isPro")
        XCTAssertTrue(storedAdmin, "bypass should persist its own flag")
        #endif
    }

    func testProductIDsMatchStoreKitConfig() throws {
        // The .storekit config ships as a test-bundle resource (see project.yml),
        // so this works on device as well as on the Mac.
        let bundle = Bundle(for: EntitlementTests.self)
        guard let url = bundle.url(forResource: "CinemaComposerPro", withExtension: "storekit") else {
            return XCTFail("CinemaComposerPro.storekit is not in the test bundle")
        }
        try verifyProductIDs(in: try Data(contentsOf: url))
    }

    private func verifyProductIDs(in data: Data) throws {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let products = try XCTUnwrap(object?["products"] as? [[String: Any]])
        // NonConsumables carry productID at the top level; subscriptions
        // nest it inside their "subscriptions" array.
        var declaredIDs: Set<String> = []
        for product in products {
            if let id = product["productID"] as? String { declaredIDs.insert(id) }
            if let subs = product["subscriptions"] as? [[String: Any]] {
                for sub in subs {
                    if let id = sub["productID"] as? String { declaredIDs.insert(id) }
                }
            }
        }
        XCTAssertFalse(declaredIDs.isEmpty, "no products in the StoreKit config")
        for declared in declaredIDs {
            XCTAssertTrue(EntitlementManager.ProductID.all.contains(declared),
                          "\(declared) is in the config but the manager doesn't know it")
        }
        for known in EntitlementManager.ProductID.all {
            XCTAssertTrue(declaredIDs.contains(known),
                          "\(known) is in the manager but missing from the config")
        }
    }
}