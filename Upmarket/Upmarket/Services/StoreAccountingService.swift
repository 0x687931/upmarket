import Foundation

struct StoreAccountingSnapshot: Equatable {
    let freeDocsRemaining: Int
    let packCredits: Int
    let packsEverPurchased: Int
    let userVisibleError: String?
}

struct StoreAccountingConsumption: Equatable {
    let consumed: Bool
    let snapshot: StoreAccountingSnapshot
}

final class StoreAccountingService {
    private let defaults: UserDefaults

    private let freeDocsRemainingKey = "upmarket.freeDocsRemaining"
    private let lastTrialPromptKey = "upmarket.lastTrialPaywallPromptRemaining"
    private let legacyPackCreditsKey = "upmarket.packCredits"
    private let legacyPacksEverPurchasedKey = "upmarket.packsEverPurchased"

    init(defaults: UserDefaults = .standard, packLedger: PackCreditLedger = PackCreditLedger()) {
        self.defaults = defaults
        _ = packLedger
    }

    func loadInitialState() -> StoreAccountingSnapshot {
        discardLegacyLocalCredits()
        return lockedSnapshot()
    }

    func consumeConversion(freeDocsRemaining: Int, packCredits: Int) throws -> StoreAccountingConsumption {
        discardLegacyLocalCredits()
        return StoreAccountingConsumption(consumed: false, snapshot: lockedSnapshot())
    }

    func shouldShowTrialPaywallAfterConversion(
        hasPaidEntitlement: Bool,
        freeDocsRemaining: Int,
        packCredits: Int
    ) -> Bool {
        return false
    }

    func recordPackTransaction(transactionID: UInt64, isRevoked: Bool, freeDocsRemaining: Int) throws -> StoreAccountingSnapshot {
        lockedSnapshot()
    }

    func snapshot(freeDocsRemaining: Int) throws -> StoreAccountingSnapshot {
        lockedSnapshot()
    }

    private func discardLegacyLocalCredits() {
        defaults.set(0, forKey: freeDocsRemainingKey)
        defaults.removeObject(forKey: lastTrialPromptKey)
        defaults.removeObject(forKey: legacyPackCreditsKey)
        defaults.removeObject(forKey: legacyPacksEverPurchasedKey)
    }

    private func lockedSnapshot() -> StoreAccountingSnapshot {
        StoreAccountingSnapshot(
            freeDocsRemaining: 0,
            packCredits: 0,
            packsEverPurchased: 0,
            userVisibleError: nil
        )
    }
}
