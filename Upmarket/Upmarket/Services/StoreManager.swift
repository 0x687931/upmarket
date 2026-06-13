import Foundation
import StoreKit
import Combine
import OSLog

final class StoreManager: ObservableObject {

    nonisolated static let shared = StoreManager()

    // Product IDs — nonisolated so they're accessible from any actor context
    nonisolated static let proID      = "com.upmarket.app.pro"
    nonisolated static let maxID      = "com.upmarket.app.max"
    nonisolated static let packID     = "com.upmarket.app.doc_pack"

    let objectWillChange = PassthroughSubject<Void, Never>()

    private(set) var proProduct:   Product?
    private(set) var maxProduct:   Product?
    private(set) var packProduct:  Product?

    private(set) var productsLoaded = false {
        willSet { objectWillChange.send() }
    }

    private(set) var productLoadError: String? {
        willSet { objectWillChange.send() }
    }

    private var isLoadingProducts = false

    private(set) var tier: AppTier = .basic {
        willSet { objectWillChange.send() }
    }

    // Beta access is granted only by verified non-consumable StoreKit entitlements.
    private(set) var freeDocsRemaining: Int = 0 {
        willSet { objectWillChange.send() }
    }

    // Purchased doc pack credits
    private(set) var packCredits: Int = 0 {
        willSet { objectWillChange.send() }
    }

    // How many packs the user has ever bought — drives nudge intensity
    private(set) var packsEverPurchased: Int = 0 {
        willSet { objectWillChange.send() }
    }

    private let accounting = StoreAccountingService()

    private var transactionListener: Task<Void, Error>?

    private init() {
        transactionListener = listenForTransactions()
        Task { await loadProducts() }
        Task { await refreshEntitlement() }
        applyAccountingSnapshot(accounting.loadInitialState())

        #if DEBUG
        Task { @MainActor in
            self.tier = .max
        }
        #endif
    }

    deinit { transactionListener?.cancel() }

    // MARK: - Debug testing

    #if DEBUG
    /// Override tier for UI testing (DEBUG only)
    func setDebugTier(_ newTier: AppTier) {
        Task { @MainActor in
            self.tier = newTier
        }
    }
    #endif

    // MARK: - Tier checks

    /// Basic tier is always available — native conversion requires no purchase.
    var canConvert: Bool { true }

    var upgradeNudge: UpgradeNudge { .none }

    /// Human-readable nudge message
    var nudgeMessage: String? {
        let spent = String(format: "$%.2f", Double(packsEverPurchased) * 0.99)
        switch upgradeNudge {
        case .none: return nil
        case .softNudge:
            return "Running low — unlimited conversions for just $4.99."
        case .strongNudge:
            return "You've bought 2 packs — unlimited is better value at $4.99."
        case .mathsNudge:
            return "You've spent \(spent) on doc packs. Unlimited is $4.99 — just \(remainingToUnlimited(spent: Double(packsEverPurchased) * 0.99)) more."
        }
    }

    // MARK: - Consuming docs

    /// Basic tier has unlimited native conversion — always succeeds.
    @discardableResult
    func consumeConversion() -> Bool { true }

    func shouldShowTrialPaywallAfterConversion() -> Bool { false }

    // MARK: - Purchasing

    func purchase(_ product: Product) async throws {
        if product.id == Self.packID {
            throw StoreError.unsupportedProduct
        }
        if product.id == Self.maxID && !FeatureFlags.shared.aiAvailable {
            throw StoreError.unsupportedDevice
        }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            if transaction.productID == Self.packID {
                try await recordPackTransaction(transaction)
            } else {
                await refreshEntitlement()
            }
            await transaction.finish()
        case .userCancelled, .pending: break
        @unknown default: break
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    func refreshEntitlementForProgrammaticConversion() async {
        await refreshEntitlement()
    }

    // MARK: - Private

    func loadProducts() async {
        guard !isLoadingProducts else { return }
        await MainActor.run {
            self.isLoadingProducts = true
            self.productLoadError = nil
        }
        defer {
            Task { @MainActor in
                self.isLoadingProducts = false
            }
        }

        do {
            let productIDs = [Self.proID, Self.maxID]
        let products = try await Product.products(for: productIDs)
            await MainActor.run {
                self.proProduct   = products.first { $0.id == Self.proID }
                self.maxProduct   = products.first { $0.id == Self.maxID }
                self.packProduct  = nil
                self.productsLoaded = true
                if self.proProduct == nil {
                    self.productLoadError = "Some purchase options are unavailable. Check StoreKit configuration or App Store Connect product IDs."
                }
            }
        } catch {
            await MainActor.run {
                self.productsLoaded = true
                self.productLoadError = "Purchase options could not be loaded."
            }
            AppLog.storeKit.error("Failed to load products: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func refreshEntitlement() async {
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.productID == Self.maxID {
                await MainActor.run { self.tier = .max }
                return
            }
            if transaction.productID == Self.proID {
                await MainActor.run { self.tier = .pro }
                return
            }
        }
        await MainActor.run { self.tier = .basic }
    }

    private func remainingToUnlimited(spent: Double) -> String {
        let remaining = max(0, 4.99 - spent)
        return String(format: "$%.2f", remaining)
    }

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                guard let transaction = try? self.checkVerified(result) else { continue }
                if transaction.productID == Self.packID {
                    do {
                        try await self.recordPackTransaction(transaction)
                    } catch {
                        await MainActor.run {
                            self.productLoadError = "A document pack purchase could not be recorded. Keep Upmarket open and try Restore Purchases."
                        }
                        AppLog.storeKit.error("Failed to record pack transaction id=\(transaction.id, privacy: .public): \(error.localizedDescription, privacy: .private)")
                        continue
                    }
                } else {
                    await self.refreshEntitlement()
                }
                await transaction.finish()
            }
        }
    }

    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw StoreError.failedVerification
        case .verified(let value): return value
        }
    }

    private func recordPackTransaction(_ transaction: Transaction) async throws {
        let snapshot = try accounting.recordPackTransaction(
            transactionID: transaction.id,
            isRevoked: transaction.revocationDate != nil,
            freeDocsRemaining: freeDocsRemaining
        )
        await MainActor.run { self.applyAccountingSnapshot(snapshot) }
    }

    private func applyAccountingSnapshot(_ snapshot: StoreAccountingSnapshot) {
        freeDocsRemaining = snapshot.freeDocsRemaining
        packCredits = snapshot.packCredits
        packsEverPurchased = snapshot.packsEverPurchased
        if let userVisibleError = snapshot.userVisibleError {
            productLoadError = userVisibleError
        }
    }
}

enum UpgradeNudge {
    case none
    case softNudge     // 1 pack bought, running low
    case strongNudge   // 2 packs bought
    case mathsNudge    // 3+ packs, show the maths
}

enum StoreError: Error {
    case failedVerification
    case unsupportedDevice
    case unsupportedProduct
}
