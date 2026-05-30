import Foundation
import StoreKit
import Combine

final class StoreManager: ObservableObject {

    static let shared = StoreManager()

    // Product IDs — never expose these strings in UI
    static let basicID    = "com.upmarket.app.basic"
    static let proID      = "com.upmarket.app.pro"
    static let aiCreditID = "com.upmarket.app.ai_credit"

    let objectWillChange = PassthroughSubject<Void, Never>()

    private(set) var basicProduct:    Product?
    private(set) var proProduct:      Product?
    private(set) var aiCreditProduct: Product?

    private(set) var entitlement: Entitlement = .none {
        willSet { objectWillChange.send() }
    }

    // Remaining single-doc AI credits (consumable)
    private(set) var aiCredits: Int = 0 {
        willSet { objectWillChange.send() }
    }

    private var transactionListener: Task<Void, Error>?

    private init() {
        transactionListener = listenForTransactions()
        Task { await loadProducts() }
        Task { await refreshEntitlement() }
        aiCredits = UserDefaults.standard.integer(forKey: "upmarket.aiCredits")
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

    /// Can use Upmarket AI — either Pro, trial, or has a credit
    var canUseAI: Bool {
        hasProOrAbove || aiCredits > 0
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
            if transaction.productID == Self.aiCreditID {
                // Consumable — add credit, finish immediately
                await MainActor.run {
                    self.aiCredits += 1
                    UserDefaults.standard.set(self.aiCredits, forKey: "upmarket.aiCredits")
                }
            } else {
                await refreshEntitlement()
            }
            await transaction.finish()
        case .userCancelled:
            break
        case .pending:
            break
        @unknown default:
            break
        }
    }

    /// Consume one AI credit. Call before running an AI conversion.
    func consumeAICredit() {
        guard aiCredits > 0 else { return }
        aiCredits -= 1
        UserDefaults.standard.set(aiCredits, forKey: "upmarket.aiCredits")
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    // MARK: - Private

    private func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.basicID, Self.proID, Self.aiCreditID])
            await MainActor.run {
                self.basicProduct    = products.first { $0.id == Self.basicID }
                self.proProduct      = products.first { $0.id == Self.proID }
                self.aiCreditProduct = products.first { $0.id == Self.aiCreditID }
            }
        } catch {
            print("[StoreManager] Failed to load products: \(error)")
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
                if transaction.productID == Self.aiCreditID {
                    await MainActor.run {
                        self.aiCredits += 1
                        UserDefaults.standard.set(self.aiCredits, forKey: "upmarket.aiCredits")
                    }
                } else {
                    await self.refreshEntitlement()
                }
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
