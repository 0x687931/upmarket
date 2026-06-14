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

        // Native (Basic) conversion is always permitted. Only the AI capability is
        // tier-gated here, matching how the app's UI gates the AI toggle — the same
        // AppTierGate used everywhere. Enhanced is auto-selected only when available,
        // so it needs no explicit guard.
        if useAI {
            let gate = await ModelManager.shared.gateAfterChecking(tier: store.tier)
            if gate.unavailableReason(for: .ai) != nil {
                throw ProgrammaticConversionAuthorizationError.aiUnavailable
            }
        }
    }
}
