import Foundation

enum ProgrammaticConversionAuthorizationError: Error, Equatable {
    case purchaseRequired
    case aiUnavailable
}

@MainActor
enum ProgrammaticConversionAuthorization {
    static func authorize(useAI: Bool) async throws {
        let store = StoreManager.shared

        await store.refreshEntitlementForProgrammaticConversion()

        if useAI {
            let gate = await ModelManager.shared.gateAfterChecking(tier: store.tier)
            if let reason = gate.unavailableReason(for: .ai) {
                throw ProgrammaticConversionAuthorizationError.aiUnavailable
            }
        }

        guard store.consumeConversion() else {
            throw ProgrammaticConversionAuthorizationError.purchaseRequired
        }
    }
}
