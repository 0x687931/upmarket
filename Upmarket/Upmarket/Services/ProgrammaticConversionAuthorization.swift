import Foundation

enum ProgrammaticConversionAuthorizationError: Error, Equatable {
    case purchaseRequired
    case aiUnavailable
}

@MainActor
enum ProgrammaticConversionAuthorization {
    static func authorize(useAI: Bool, aiEngine: AIEngine? = nil) async throws {
        let store = StoreManager.shared

        await store.refreshEntitlementForProgrammaticConversion()

        // Native (Basic) conversion is always permitted. Only the AI capability is
        // tier-gated here, matching how the app's UI gates the AI toggle — the same
        // AppTierGate used everywhere. Enhanced is auto-selected only when available,
        // so it needs no explicit guard.
        if useAI {
            let engine = aiEngine ?? AIEngine.selected
            _ = await ModelManager.shared.gateAfterChecking(tier: store.tier)
            var downloadedAssets = ModelManager.shared.downloadedAssets
            if engine == .lfm2 {
                if downloadedAssets.contains(engine.asset) {
                    downloadedAssets.insert(.upmarketAI)
                } else {
                    downloadedAssets.remove(.upmarketAI)
                }
            }
            let gate = AppTierGate(
                tier: store.tier,
                downloadedAssets: downloadedAssets,
                deviceSupportsRuntime: DeviceCapability.shared.isAppleSilicon,
                aiFeatureEnabled: FeatureFlags.shared.aiAvailable,
                aiFeatureUnavailableReason: FeatureFlags.shared.aiUnavailableReason
            )
            if gate.unavailableReason(for: .ai) != nil {
                throw ProgrammaticConversionAuthorizationError.aiUnavailable
            }
        }
    }
}
