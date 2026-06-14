import XCTest
@testable import Upmarket

/// THE tier contract, enforced. `AppTier` is the single source of truth for tiers,
/// product IDs, and prices. `Store.storekit` (and, in production, App Store Connect)
/// must agree with it. If a test here fails, a tier definition drifted — fix `AppTier`
/// first, then make the others match. Do not weaken these assertions to make them pass.
final class AppTierContractTests: XCTestCase {

    private struct StoreKitFile: Decodable {
        struct Product: Decodable {
            let productID: String
            let displayPrice: String
        }
        let nonConsumableProducts: [Product]
        let products: [Product]
    }

    private func loadStoreKit() throws -> StoreKitFile {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UpmarketTests/
            .deletingLastPathComponent()   // Upmarket/ (project dir)
            .appendingPathComponent("Upmarket/Store.storekit")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(StoreKitFile.self, from: data)
    }

    /// Paid tiers and expected price, derived from AppTier (the source of truth).
    private let expectedPaidProducts: [String: String] = [
        AppTier.proProductID: AppTier.pro.price,
        AppTier.maxProductID: AppTier.max.price,
    ]

    func testStoreKitProductsMatchAppTierExactly() throws {
        let file = try loadStoreKit()

        // 1. Every paid tier maps to exactly one non-consumable at the AppTier price.
        for (productID, price) in expectedPaidProducts {
            let matches = file.nonConsumableProducts.filter { $0.productID == productID }
            XCTAssertEqual(matches.count, 1,
                           "Store.storekit must contain exactly one non-consumable \(productID)")
            if let product = matches.first {
                XCTAssertEqual("$" + product.displayPrice, price,
                               "\(productID) price in Store.storekit ($\(product.displayPrice)) must match AppTier (\(price))")
            }
        }

        // 2. No product AppTier doesn't know about (catches stray basic / doc_pack).
        let known = Set(expectedPaidProducts.keys)
        for product in file.nonConsumableProducts + file.products {
            XCTAssertTrue(known.contains(product.productID),
                          "Store.storekit contains \(product.productID), unknown to AppTier. Remove it or add it to AppTier.")
        }

        // 3. The consumable doc-pack economy was removed — no consumables allowed.
        XCTAssertTrue(file.products.isEmpty, "Store.storekit must not define consumable products.")
    }

    func testStoreManagerIDsAreDerivedFromAppTier() {
        XCTAssertEqual(StoreManager.proID, AppTier.proProductID)
        XCTAssertEqual(StoreManager.maxID, AppTier.maxProductID)
    }

    func testBasicTierIsFreeWithNoProduct() {
        XCTAssertNil(AppTier.basic.productID)
        XCTAssertEqual(AppTier.pro.productID, AppTier.proProductID)
        XCTAssertEqual(AppTier.max.productID, AppTier.maxProductID)
    }
}
