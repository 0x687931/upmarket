import XCTest
@testable import Upmarket

/// THE tier contract, enforced. `AppTier` is the single source of truth for tiers,
/// product IDs, prices, and the document-type → tier matrix. `Store.storekit` (and, in
/// production, App Store Connect) must agree with it. If a test here fails, a tier
/// definition drifted — fix `AppTier` first, then make the others match. Do not weaken
/// these assertions to make them pass.
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
        return try JSONDecoder().decode(StoreKitFile.self, from: Data(contentsOf: url))
    }

    /// Numeric amount only, ignoring currency symbol (real currency is per-storefront).
    private func amount(_ s: String) -> String { s.filter { $0.isNumber || $0 == "." } }

    /// All three tiers are paid non-consumables (no free tier; the app is free to
    /// download with a 5-conversion trial). Derived from AppTier (source of truth).
    private let expectedProducts: [String: String] = [
        AppTier.basicProductID: AppTier.basic.price,
        AppTier.proProductID:   AppTier.pro.price,
        AppTier.maxProductID:   AppTier.max.price,
    ]

    func testStoreKitProductsMatchAppTierExactly() throws {
        let file = try loadStoreKit()

        for (productID, price) in expectedProducts {
            let matches = file.nonConsumableProducts.filter { $0.productID == productID }
            XCTAssertEqual(matches.count, 1, "Store.storekit must contain exactly one non-consumable \(productID)")
            if let product = matches.first {
                XCTAssertEqual(amount(product.displayPrice), amount(price),
                               "\(productID) price in Store.storekit (\(product.displayPrice)) must match AppTier (\(price))")
            }
        }

        let known = Set(expectedProducts.keys)
        for product in file.nonConsumableProducts + file.products {
            XCTAssertTrue(known.contains(product.productID),
                          "Store.storekit contains \(product.productID), unknown to AppTier.")
        }
        XCTAssertTrue(file.products.isEmpty, "Store.storekit must not define consumable products.")
    }

    func testAllTiersArePaidWithDistinctProductIDs() {
        let ids = [AppTier.basic.productID, AppTier.pro.productID, AppTier.max.productID]
        XCTAssertEqual(Set(ids).count, 3, "Each tier must have a distinct product ID")
        XCTAssertEqual(StoreManager.basicID, AppTier.basicProductID)
        XCTAssertEqual(StoreManager.proID, AppTier.proProductID)
        XCTAssertEqual(StoreManager.maxID, AppTier.maxProductID)
    }

    /// Document-type → tier matrix (the upgrade-funnel contract).
    func testDocumentTypeTierMatrix() {
        // Pro-only formats: spreadsheets, presentations (incl. legacy .xls/.ppt), ebooks,
        // audio, and structured formats with no native engine (JSON/XML/ZIP/WebVTT/AsciiDoc
        // require the advanced runtime).
        let proFormats: [ConversionFormat] = [
            .xlsx, .pptx, .xls, .ppt, .epub, .mp3, .m4a, .wav, .aiff,
            .json, .xml, .zip, .webvtt, .asciidoc,
        ]
        for fmt in proFormats {
            XCTAssertEqual(AppTier.requiredTier(for: fmt), .pro, "\(fmt) must require Pro")
        }
        // Basic formats: everyday documents (incl. legacy .doc), text, HTML, images, and PDF
        // — all served by in-process native engines (complexity is layered on separately by
        // ConversionCapability).
        let basicFormats: [ConversionFormat] = [.txt, .md, .docx, .doc, .html, .csv, .pdf, .png, .jpg, .jpeg]
        for fmt in basicFormats {
            XCTAssertEqual(AppTier.requiredTier(for: fmt), .basic, "\(fmt) must be Basic")
        }
    }
}
