import Foundation
import StoreKit
import Combine
import OSLog

/// The app's single StoreKit authority. Tier is derived entirely from verified
/// non-consumable entitlements (Pro, Max); Basic is the default and needs no purchase.
///
/// This is the ONLY process that talks to StoreKit. The CLI and MCP surfaces get
/// their tier by routing conversions through the in-app broker (see CLIConversionBroker)
/// — they never read entitlements themselves, because StoreKit only resolves against
/// this app bundle's receipt.
final class StoreManager: ObservableObject {

    nonisolated static let shared = StoreManager()

    // Product IDs — nonisolated so they're accessible from any actor context.
    // Source of truth for these IDs is AppTier.productID; Store.storekit must match
    // (enforced by AppTierContractTests).
    nonisolated static let proID = AppTier.proProductID
    nonisolated static let maxID = AppTier.maxProductID

    let objectWillChange = PassthroughSubject<Void, Never>()

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

    private var transactionListener: Task<Void, Error>?

    private init() {
        transactionListener = listenForTransactions()
        Task { await loadProducts() }
        Task { await refreshEntitlement() }
        // No DEBUG tier override here: local builds start at Basic (the honest
        // unpaid default). Use Preferences → Debug Tier Override (setDebugTier)
        // to exercise Pro/Max locally. See StoreManagerTests.
    }

    deinit { transactionListener?.cancel() }

    // MARK: - Debug testing

    #if DEBUG
    /// Override the tier locally to test paid/unpaid access without real purchases.
    /// Drives the Preferences → Debug Tier Override buttons. DEBUG only.
    func setDebugTier(_ newTier: AppTier) {
        Task { @MainActor in
            self.tier = newTier
        }
    }
    #endif

    // MARK: - Tier checks

    /// Every tier can convert — Basic does native Apple conversion for free.
    /// Per-capability gating (Enhanced/AI) lives in AppTierGate, not here.
    var canConvert: Bool { true }

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
            let products = try await Product.products(for: [Self.proID, Self.maxID])
            await MainActor.run {
                self.proProduct = products.first { $0.id == Self.proID }
                self.maxProduct = products.first { $0.id == Self.maxID }
                self.productsLoaded = true
                if self.proProduct == nil || self.maxProduct == nil {
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
        // Highest owned entitlement wins.
        var resolved: AppTier = .basic
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.productID == Self.maxID {
                resolved = .max
                break
            }
            if transaction.productID == Self.proID, resolved < .pro {
                resolved = .pro
            }
        }
        await MainActor.run { self.tier = resolved }
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
