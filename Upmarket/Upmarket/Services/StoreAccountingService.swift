import Foundation
import OSLog

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
    private let packLedger: PackCreditLedger

    private let freeDocsRemainingKey = "upmarket.freeDocsRemaining"
    private let lastTrialPromptKey = "upmarket.lastTrialPaywallPromptRemaining"
    private let legacyPackCreditsKey = "upmarket.packCredits"
    private let legacyPacksEverPurchasedKey = "upmarket.packsEverPurchased"

    init(defaults: UserDefaults = .standard, packLedger: PackCreditLedger = PackCreditLedger()) {
        self.defaults = defaults
        self.packLedger = packLedger
    }

    func loadInitialState() -> StoreAccountingSnapshot {
        let freeDocs = defaults.object(forKey: freeDocsRemainingKey) as? Int ?? 3
        do {
            let migrated = try migrateLegacyPackCreditsIfNeeded(freeDocsRemaining: freeDocs)
            if let migrated { return migrated }
            return try snapshot(freeDocsRemaining: freeDocs)
        } catch {
            AppLog.storeKit.error("Failed to load purchase accounting: \(error.localizedDescription, privacy: .private)")
            return StoreAccountingSnapshot(
                freeDocsRemaining: freeDocs,
                packCredits: 0,
                packsEverPurchased: 0,
                userVisibleError: "Purchase records could not be read. Please contact support before buying another document pack."
            )
        }
    }

    func consumeConversion(freeDocsRemaining: Int, packCredits: Int) throws -> StoreAccountingConsumption {
        if freeDocsRemaining > 0 {
            let remaining = freeDocsRemaining - 1
            defaults.set(remaining, forKey: freeDocsRemainingKey)
            return StoreAccountingConsumption(
                consumed: true,
                snapshot: try snapshot(freeDocsRemaining: remaining)
            )
        }

        guard packCredits > 0 else {
            return StoreAccountingConsumption(
                consumed: false,
                snapshot: try snapshot(freeDocsRemaining: freeDocsRemaining)
            )
        }

        guard try packLedger.consumeCredit() else {
            return StoreAccountingConsumption(
                consumed: false,
                snapshot: try snapshot(freeDocsRemaining: freeDocsRemaining)
            )
        }
        return StoreAccountingConsumption(
            consumed: true,
            snapshot: try snapshot(freeDocsRemaining: freeDocsRemaining)
        )
    }

    func shouldShowTrialPaywallAfterConversion(
        hasPaidEntitlement: Bool,
        freeDocsRemaining: Int,
        packCredits: Int
    ) -> Bool {
        guard !hasPaidEntitlement, packCredits == 0, freeDocsRemaining <= 1 else { return false }
        let lastPrompted = defaults.object(forKey: lastTrialPromptKey) as? Int
        guard lastPrompted != freeDocsRemaining else { return false }
        defaults.set(freeDocsRemaining, forKey: lastTrialPromptKey)
        return true
    }

    func recordPackTransaction(transactionID: UInt64, isRevoked: Bool, freeDocsRemaining: Int) throws -> StoreAccountingSnapshot {
        if isRevoked {
            _ = try packLedger.revokePackPurchase(transactionID: transactionID)
        } else {
            _ = try packLedger.recordPackPurchase(transactionID: transactionID)
        }
        return try snapshot(freeDocsRemaining: freeDocsRemaining)
    }

    func snapshot(freeDocsRemaining: Int) throws -> StoreAccountingSnapshot {
        let packSnapshot = try packLedger.snapshot()
        return StoreAccountingSnapshot(
            freeDocsRemaining: freeDocsRemaining,
            packCredits: packSnapshot.availableCredits,
            packsEverPurchased: packSnapshot.purchasedPackCount,
            userVisibleError: nil
        )
    }

    private func migrateLegacyPackCreditsIfNeeded(freeDocsRemaining: Int) throws -> StoreAccountingSnapshot? {
        let snapshot = try packLedger.snapshot()
        guard !snapshot.legacyMigrationComplete else { return nil }

        let credits = defaults.integer(forKey: legacyPackCreditsKey)
        let packs = defaults.integer(forKey: legacyPacksEverPurchasedKey)
        let migrated = try packLedger.migrateLegacyCredits(credits: credits, packsEverPurchased: packs)
        defaults.removeObject(forKey: legacyPackCreditsKey)
        defaults.removeObject(forKey: legacyPacksEverPurchasedKey)

        return StoreAccountingSnapshot(
            freeDocsRemaining: freeDocsRemaining,
            packCredits: migrated.availableCredits,
            packsEverPurchased: migrated.purchasedPackCount,
            userVisibleError: nil
        )
    }
}
