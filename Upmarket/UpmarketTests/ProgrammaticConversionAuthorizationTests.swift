import XCTest
@testable import Upmarket

/// Authorization contract for programmatic (CLI/MCP) conversions: native is always
/// allowed (Basic converts for free); only the AI capability is tier/availability gated.
/// There is no per-conversion credit or purchase wall.
@MainActor
final class ProgrammaticConversionAuthorizationTests: XCTestCase {

    func testNativeConversionIsAlwaysAuthorized() async throws {
        // Basic tier does native conversion for free, so this must never throw.
        try await ProgrammaticConversionAuthorization.authorize(useAI: false)
    }

    func testAIConversionEitherSucceedsOrReportsUnavailable() async {
        // The only acceptable failure for AI is aiUnavailable (device/tier/model).
        // purchaseRequired must NOT be thrown — there is no per-conversion purchase wall.
        do {
            try await ProgrammaticConversionAuthorization.authorize(useAI: true)
        } catch ProgrammaticConversionAuthorizationError.aiUnavailable {
            // Expected when AI isn't available on this machine / tier.
        } catch {
            XCTFail("AI authorization should only fail with .aiUnavailable, got: \(error)")
        }
    }
}
