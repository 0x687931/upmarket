import Foundation
import StoreKit
import Combine

final class StoreManager: ObservableObject {

    static let shared = StoreManager()

    // Product IDs
    static let basicID = "com.upmarket.app.basic"
    static let proID   = "com.upmarket.app.pro"

    let objectWillChange = PassthroughSubject<Void, Never>()

    private(set) var basicProduct: Product?
    private(set) var proProduct: Product?

    private(set) var entitlement: Entitlement = .none {
        willSet { objectWillChange.send() }
    }

    private var transactionListener: Task<Void, Error>?

    private init() {
        transactionListener = listenForTransactions()
        Task { await loadProducts() }
        Task { await refreshEntitlement() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Public

    var isTrialActive: Bool {
        if case .trial = entitlement { return true }
        return false
    }

    var hasBasicOrAbove: Bool {
        switch entitlement {
        case .none: return false
        case .trial, .basic, .pro: return true
        }
    }

    var hasProOrAbove: Bool {
        switch entitlement {
        case .pro, .trial: return true
        default: return false
        }
    }

    var trialDaysRemaining: Int? {
        if case .trial(let days) = entitlement { return days }
        return nil
    }

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await refreshEntitlement()
            await transaction.finish()
        case .userCancelled:
            break
        case .pending:
            break
        @unknown default:
            break
        }
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    // MARK: - Private

    private func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.basicID, Self.proID])
            await MainActor.run {
                self.basicProduct = products.first { $0.id == Self.basicID }
                self.proProduct   = products.first { $0.id == Self.proID }
            }
        } catch {
            print("[StoreManager] Failed to load products: \(error)")
        }
    }

    private func refreshEntitlement() async {
        // Check for paid purchases first
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

        // No purchase — check trial window (7 days from first launch)
        let days = trialDaysRemainingFromFirstLaunch()
        if days > 0 {
            await MainActor.run { self.entitlement = .trial(daysRemaining: days) }
        } else {
            await MainActor.run { self.entitlement = .none }
        }
    }

    private func trialDaysRemainingFromFirstLaunch() -> Int {
        let key = "upmarket.firstLaunchDate"
        let now = Date()

        if UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(now, forKey: key)
        }

        let firstLaunch = UserDefaults.standard.object(forKey: key) as? Date ?? now
        let elapsed = Calendar.current.dateComponents([.day], from: firstLaunch, to: now).day ?? 0
        return max(0, 7 - elapsed)
    }

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                guard let transaction = try? self.checkVerified(result) else { continue }
                await self.refreshEntitlement()
                await transaction.finish()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let value):
            return value
        }
    }
}

// MARK: - Models

enum Entitlement: Equatable {
    case none
    case trial(daysRemaining: Int)
    case basic
    case pro
}

enum StoreError: Error {
    case failedVerification
}
