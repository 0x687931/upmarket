import Foundation

enum ProgrammaticConversionAuthorizationError: Error, Equatable {
    case purchaseRequired
    case aiUnavailable
}

@MainActor
struct ProgrammaticConversionAuthorizer {
    typealias RefreshEntitlements = () async -> Void
    typealias AIUnavailableReason = (_ useAI: Bool) async -> String?
    typealias ConsumeConversion = () -> Bool

    let refreshEntitlements: RefreshEntitlements
    let aiUnavailableReason: AIUnavailableReason
    let consumeConversion: ConsumeConversion

    func authorize(useAI: Bool) async throws {
        await refreshEntitlements()

        if await aiUnavailableReason(useAI) != nil {
            throw ProgrammaticConversionAuthorizationError.aiUnavailable
        }

        guard consumeConversion() else {
            throw ProgrammaticConversionAuthorizationError.purchaseRequired
        }
    }
}

@MainActor
enum ProgrammaticConversionAuthorization {
    static func authorize(useAI: Bool) async throws {
        let store = StoreManager.shared
        let authorizer = ProgrammaticConversionAuthorizer(
            refreshEntitlements: {
                await store.refreshEntitlementForProgrammaticConversion()
            },
            aiUnavailableReason: { useAI in
                guard useAI else { return nil }
                return await ModelManager.shared.aiUseUnavailableReasonAfterChecking(hasPro: store.hasProOrAbove)
            },
            consumeConversion: {
                store.consumeConversion()
            }
        )
        try await authorizer.authorize(useAI: useAI)
    }
}
