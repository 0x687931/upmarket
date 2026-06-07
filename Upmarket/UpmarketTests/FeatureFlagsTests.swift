import XCTest
@testable import Upmarket

final class FeatureFlagsTests: XCTestCase {
    func testFetchAppliesCloudKitPayload() {
        let payload = FeatureFlagPayload(
            aiSupportedLocales: ["en", "ja"],
            aiExperimentalLocales: ["ko"],
            version: 7
        )
        let flags = FeatureFlags(
            fetcher: StubFeatureFlagFetcher(result: .success(payload)),
            deliverUpdate: { update in update() }
        )

        flags.fetchFlags()

        XCTAssertEqual(flags.aiSupportedLocales, ["en", "ja"])
        XCTAssertEqual(flags.aiExperimentalLocales, ["ko"])
        XCTAssertEqual(flags.flagsVersion, 7)
    }

    func testFetchFailureKeepsBundledFallbacks() {
        let flags = FeatureFlags(
            fetcher: StubFeatureFlagFetcher(result: .failure(TestError.failed)),
            deliverUpdate: { update in update() }
        )

        flags.fetchFlags()

        XCTAssertEqual(flags.aiSupportedLocales, FeatureFlags.fallbackSupportedLocales)
        XCTAssertEqual(flags.aiExperimentalLocales, FeatureFlags.fallbackExperimentalLocales)
        XCTAssertEqual(flags.flagsVersion, 0)
    }

    func testBundledFallbacksTrackValidatedClaimsOnly() {
        XCTAssertEqual(FeatureFlags.fallbackSupportedLocales, ["en"])
        XCTAssertEqual(FeatureFlags.fallbackExperimentalLocales, ["ar", "ja", "zh"])
        XCTAssertFalse(FeatureFlags.fallbackSupportedLocales.contains("fr"))
        XCTAssertFalse(FeatureFlags.fallbackExperimentalLocales.contains("ko"))
    }

    func testCloudKitEntitlementsRequireFeatureFlagContainerAndService() {
        XCTAssertTrue(FeatureFlagCloudKitEntitlements(
            containerIdentifiers: ["iCloud.com.upmarket.app"],
            services: ["CloudKit"]
        ).canFetchFeatureFlags)

        XCTAssertFalse(FeatureFlagCloudKitEntitlements(
            containerIdentifiers: [],
            services: ["CloudKit"]
        ).canFetchFeatureFlags)

        XCTAssertFalse(FeatureFlagCloudKitEntitlements(
            containerIdentifiers: ["iCloud.com.upmarket.app"],
            services: []
        ).canFetchFeatureFlags)
    }

    func testCloudKitFetcherFailsBeforeContainerCreationWithoutEntitlement() {
        let fetcher = CloudKitFeatureFlagFetcher(entitlements: {
            FeatureFlagCloudKitEntitlements(containerIdentifiers: [], services: [])
        })
        let expectation = expectation(description: "CloudKit fetch fails synchronously")

        fetcher.fetchFeatureFlags { result in
            guard case .failure = result else {
                XCTFail("Expected missing entitlement failure")
                return
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 0.1)
    }
}

private struct StubFeatureFlagFetcher: FeatureFlagFetching {
    let result: Result<FeatureFlagPayload, Error>

    func fetchFeatureFlags(completion: @escaping (Result<FeatureFlagPayload, Error>) -> Void) {
        completion(result)
    }
}

private enum TestError: Error {
    case failed
}
