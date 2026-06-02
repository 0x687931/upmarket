import Foundation
import StoreKit
import Combine
import OSLog

final class StoreManager: ObservableObject {

    static let shared = StoreManager()

    // Product IDs — nonisolated so they're accessible from any actor context
    nonisolated static let basicID    = "com.upmarket.app.basic"
    nonisolated static let proID      = "com.upmarket.app.pro"
    nonisolated static let packID     = "com.upmarket.app.doc_pack"

    let objectWillChange = PassthroughSubject<Void, Never>()

    private(set) var basicProduct: Product?
    private(set) var proProduct:   Product?
    private(set) var packProduct:  Product?

    private(set) var productsLoaded = false {
        willSet { objectWillChange.send() }
    }

    private(set) var productLoadError: String? {
        willSet { objectWillChange.send() }
    }

    private var isLoadingProducts = false

    private(set) var entitlement: Entitlement = .none {
        willSet { objectWillChange.send() }
    }

    // Free trial: 3 docs, counted down
    private(set) var freeDocsRemaining: Int = 3 {
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
    }

    deinit { transactionListener?.cancel() }

    // MARK: - Entitlement checks

    var hasBasicOrAbove: Bool {
        switch entitlement {
        case .none: return false
        case .basic, .pro: return true
        }
    }

    var hasProOrAbove: Bool {
        entitlement == .pro
    }

    /// Can convert right now — has unlimited access, free docs, or pack credits
    var canConvert: Bool {
        hasBasicOrAbove || freeDocsRemaining > 0 || packCredits > 0
    }

    /// Nudge level based on pack purchase history
    var upgradeNudge: UpgradeNudge {
        guard !hasBasicOrAbove else { return .none }

        if packCredits <= 2 && packsEverPurchased >= 1 {
            // Running low on a pack they bought
            if packsEverPurchased >= 3 {
                return .mathsNudge  // "You've spent $X, unlimited is just $Y more"
            } else if packsEverPurchased >= 2 {
                return .strongNudge  // "You've bought 2 packs — unlimited is better value"
            } else {
                return .softNudge    // "Running low — unlimited for $4.99"
            }
        }
        return .none
    }

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

    /// Call before each conversion. Returns false if user has no access.
    @discardableResult
    func consumeConversion() -> Bool {
        if hasBasicOrAbove { return true }  // unlimited — nothing to consume

        do {
            let result = try accounting.consumeConversion(
                freeDocsRemaining: freeDocsRemaining,
                packCredits: packCredits
            )
            applyAccountingSnapshot(result.snapshot)
            return result.consumed
        } catch {
            productLoadError = "Purchase records could not be read. Please contact support before buying another document pack."
            AppLog.storeKit.error("Failed to consume conversion accounting: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    /// Trial is document-count based: 3 free conversions, then paid access.
    /// Prompt at good moments after a conversion finishes: 1 remaining, then 0.
    func shouldShowTrialPaywallAfterConversion() -> Bool {
        accounting.shouldShowTrialPaywallAfterConversion(
            hasPaidEntitlement: hasBasicOrAbove,
            freeDocsRemaining: freeDocsRemaining,
            packCredits: packCredits
        )
    }

    // MARK: - Purchasing

    func purchase(_ product: Product) async throws {
        if product.id == Self.proID && !FeatureFlags.shared.aiAvailable {
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
            let products = try await Product.products(for: [Self.basicID, Self.proID, Self.packID])
            await MainActor.run {
                self.basicProduct = products.first { $0.id == Self.basicID }
                self.proProduct   = products.first { $0.id == Self.proID }
                self.packProduct  = products.first { $0.id == Self.packID }
                self.productsLoaded = true
                if self.basicProduct == nil || self.proProduct == nil || self.packProduct == nil {
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
            if transaction.productID == Self.proID {
                await MainActor.run { self.entitlement = .pro }
                return
            }
            if transaction.productID == Self.basicID {
                await MainActor.run { self.entitlement = .basic }
                return
            }
        }
        // No paid plan — free tier
        await MainActor.run { self.entitlement = .none }
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
}
