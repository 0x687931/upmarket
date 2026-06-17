import Foundation
import StoreKit
import Combine
import OSLog

/// The app's single StoreKit authority. Tier is derived entirely from verified
/// non-consumable entitlements (Pro, Max); Basic is the default and needs no purchase.
///
/// This is the ONLY process that talks to StoreKit. It persists the resolved tier to a
/// TierSnapshot so out-of-process tools (CLI/MCP) can gate themselves — they never read
/// entitlements directly, because StoreKit only resolves against this app's receipt.
/// The app is free to download with a 5-conversion trial; after that a tier is required.
final class StoreManager: ObservableObject {

    nonisolated static let shared = StoreManager()

    // Product IDs — nonisolated so they're accessible from any actor context.
    // Source of truth for these IDs is AppTier.productID; Store.storekit must match
    // (enforced by AppTierContractTests).
    nonisolated static let basicID = AppTier.basicProductID
    nonisolated static let proID = AppTier.proProductID
    nonisolated static let maxID = AppTier.maxProductID

    let objectWillChange = PassthroughSubject<Void, Never>()

    private(set) var basicProduct: Product?
    private(set) var proProduct: Product?
    private(set) var maxProduct: Product?

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

    /// True once any tier is purchased. When false, the user is in the free trial.
    private(set) var isPurchased = false {
        willSet { objectWillChange.send() }
    }

    private let trialLimit = 5
    private let trialUsedKey = "upmarket.trialConversionsUsed"

    /// Free conversions left before the paywall (only meaningful while !isPurchased).
    var trialConversionsRemaining: Int {
        max(0, trialLimit - UserDefaults.standard.integer(forKey: trialUsedKey))
    }

    private var transactionListener: Task<Void, Error>?

    private init() {
        transactionListener = listenForTransactions()
#if DEBUG
        // A purchased tier written to the shared snapshot (scripts/dev/set_debug_tier.sh, or
        // Preferences → Debug Tier Override) is honored as a sticky local override, so the app,
        // CLI, and MCP all read Pro/Max from the same file with no purchase and no GUI clicking.
        applyDebugTierOverride()
#endif
        Task { await loadProducts() }
        Task { await refreshEntitlement() }
    }

    deinit { transactionListener?.cancel() }

    // MARK: - Debug testing

    #if DEBUG
    /// True while a local debug tier override is in effect; keeps the StoreKit refresh from
    /// clobbering it (and the snapshot the CLI/MCP read).
    private var debugTierActive = false

    /// Override the tier locally to test paid/unpaid access without real purchases.
    /// Drives the Preferences → Debug Tier Override buttons. DEBUG only.
    func setDebugTier(_ newTier: AppTier) {
        Task { @MainActor in
            self.tier = newTier
            self.isPurchased = true   // debug override behaves like a purchase
            self.debugTierActive = true
            self.writeSnapshot()
        }
    }

    /// Applies a sticky tier from the shared snapshot at launch (purchased + tier > basic only,
    /// so the app's own unpaid snapshot writes are never misread as an override). Set it from a
    /// shell with `scripts/dev/set_debug_tier.sh max` — the app, CLI, and MCP then all agree.
    private func applyDebugTierOverride() {
        guard let snap = TierSnapshot.read(), snap.purchased,
              let overridden = AppTier(rawValue: snap.tier), overridden > .basic else { return }
        tier = overridden
        isPurchased = true
        debugTierActive = true
    }
    #endif

    // MARK: - Tier checks

    /// Every tier can convert — Basic does native Apple conversion. Per-capability gating
    /// (Enhanced/AI) lives in AppTierGate; the trial limit is consumeTrialConversion().
    var canConvert: Bool { true }

    /// Call before a conversion. Purchased users are unlimited; trial users get
    /// `trialLimit` free conversions, then this returns false (caller shows the paywall).
    @discardableResult
    func consumeTrialConversion() -> Bool {
        if isPurchased { return true }
        let used = UserDefaults.standard.integer(forKey: trialUsedKey)
        guard used < trialLimit else { return false }
        UserDefaults.standard.set(used + 1, forKey: trialUsedKey)
        objectWillChange.send()
        return true
    }

    /// Persists the resolved tier for out-of-process tools (CLI/MCP). MainActor.
    private func writeSnapshot() {
        TierSnapshot(tier: tier.rawValue, purchased: isPurchased).write()
    }

    // MARK: - Purchasing

    func purchase(_ product: Product) async throws {
        if product.id == Self.maxID && !FeatureFlags.shared.aiAvailable {
            throw StoreError.unsupportedDevice
        }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await refreshEntitlement()
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
            let products = try await Product.products(for: [Self.basicID, Self.proID, Self.maxID])
            await MainActor.run {
                self.basicProduct = products.first { $0.id == Self.basicID }
                self.proProduct = products.first { $0.id == Self.proID }
                self.maxProduct = products.first { $0.id == Self.maxID }
                self.productsLoaded = true
                if self.basicProduct == nil || self.proProduct == nil || self.maxProduct == nil {
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
#if DEBUG
        // A local debug tier override is the source of truth; don't let StoreKit reset it.
        if debugTierActive { return }
#endif
        // Highest owned entitlement wins; any ownership ends the trial.
        var resolved: AppTier = .basic
        var purchased = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            switch transaction.productID {
            case Self.maxID: resolved = .max; purchased = true
            case Self.proID: if resolved < .pro { resolved = .pro }; purchased = true
            case Self.basicID: purchased = true
            default: break
            }
        }
        let finalTier = resolved, finalPurchased = purchased
        await MainActor.run {
            self.tier = finalTier
            self.isPurchased = finalPurchased
            self.writeSnapshot()
        }
    }

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                guard (try? self.checkVerified(result)) != nil else { continue }
                await self.refreshEntitlement()
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
            }
        }
    }

    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified: throw StoreError.failedVerification
        case .verified(let value): return value
        }
    }
}

enum StoreError: Error {
    case failedVerification
    case unsupportedDevice
}
