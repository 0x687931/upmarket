import Foundation
import Combine
import CloudKit
import Security

struct FeatureFlagPayload: Equatable {
    let aiSupportedLocales: Set<String>
    let aiExperimentalLocales: Set<String>
    let version: Int
}

protocol FeatureFlagFetching {
    func fetchFeatureFlags(completion: @escaping (Result<FeatureFlagPayload, Error>) -> Void)
}

struct FeatureFlagCloudKitEntitlements: Equatable {
    nonisolated static let requiredContainerIdentifier = "iCloud.com.upmarket.app"

    let containerIdentifiers: Set<String>
    let services: Set<String>

    nonisolated var canFetchFeatureFlags: Bool {
        containerIdentifiers.contains(Self.requiredContainerIdentifier)
            && services.contains("CloudKit")
    }

    nonisolated static func current() -> FeatureFlagCloudKitEntitlements {
        guard let task = SecTaskCreateFromSelf(nil) else {
            return FeatureFlagCloudKitEntitlements(containerIdentifiers: [], services: [])
        }

        return FeatureFlagCloudKitEntitlements(
            containerIdentifiers: entitlementStrings(
                "com.apple.developer.icloud-container-identifiers",
                task: task
            ),
            services: entitlementStrings(
                "com.apple.developer.icloud-services",
                task: task
            )
        )
    }

    private nonisolated static func entitlementStrings(_ name: String, task: SecTask) -> Set<String> {
        guard let value = SecTaskCopyValueForEntitlement(task, name as CFString, nil) else {
            return []
        }
        if let strings = value as? [String] {
            return Set(strings)
        }
        if let string = value as? String {
            return [string]
        }
        return []
    }
}

struct CloudKitFeatureFlagFetcher: FeatureFlagFetching {
    private static let containerIdentifier = "iCloud.com.upmarket.app"
    private static let recordName = "global"

    private let containerIdentifier: String
    private let entitlements: () -> FeatureFlagCloudKitEntitlements

    init(
        containerIdentifier: String = Self.containerIdentifier,
        entitlements: @escaping () -> FeatureFlagCloudKitEntitlements = FeatureFlagCloudKitEntitlements.current
    ) {
        self.containerIdentifier = containerIdentifier
        self.entitlements = entitlements
    }

    func fetchFeatureFlags(completion: @escaping (Result<FeatureFlagPayload, Error>) -> Void) {
        guard entitlements().canFetchFeatureFlags else {
            completion(.failure(CloudKitFeatureFlagError.missingCloudKitEntitlement))
            return
        }

        let recordID = CKRecord.ID(recordName: Self.recordName)
        let database = CKContainer(identifier: containerIdentifier).publicCloudDatabase
        database.fetch(withRecordID: recordID) { record, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let record else {
                completion(.failure(CloudKitFeatureFlagError.missingRecord))
                return
            }

            let supported = (record["ai_supported_locales"] as? [String])
                .map(Set.init) ?? FeatureFlags.fallbackSupportedLocales
            let experimental = (record["ai_experimental_locales"] as? [String])
                .map(Set.init) ?? FeatureFlags.fallbackExperimentalLocales
            let version = (record["version"] as? NSNumber)?.intValue
                ?? record["version"] as? Int
                ?? 0

            completion(.success(FeatureFlagPayload(
                aiSupportedLocales: supported,
                aiExperimentalLocales: experimental,
                version: version
            )))
        }
    }
}

enum CloudKitFeatureFlagError: Error {
    case missingRecord
    case missingCloudKitEntitlement
}

/// Remote feature flags fetched at launch from CloudKit public database.
/// Controls which UI locales support Upmarket AI without requiring an app update.
/// Falls back to a conservative hardcoded allowlist if fetch fails.
final class FeatureFlags: ObservableObject {

    static let shared = FeatureFlags()

    // Conservative fallback based on Granite Docling's model-language claim.
    // CloudKit may widen this only after Upmarket's shipped pipeline has passed
    // release validation for the locale.
    static let fallbackSupportedLocales: Set<String> = [
        "en"
    ]

    // Upstream-explicit early support, not Upmarket-supported until validated.
    static let fallbackExperimentalLocales: Set<String> = [
        "ar", "ja", "zh"
    ]

    private let fetcher: any FeatureFlagFetching
    private let deliverUpdate: (@escaping () -> Void) -> Void

    let objectWillChange = PassthroughSubject<Void, Never>()

    private(set) var aiSupportedLocales: Set<String> = fallbackSupportedLocales {
        willSet { objectWillChange.send() }
    }

    private(set) var aiExperimentalLocales: Set<String> = fallbackExperimentalLocales {
        willSet { objectWillChange.send() }
    }

    private(set) var flagsVersion: Int = 0

    init(
        fetcher: any FeatureFlagFetching = CloudKitFeatureFlagFetcher(),
        deliverUpdate: @escaping (@escaping () -> Void) -> Void = { update in
            DispatchQueue.main.async(execute: update)
        }
    ) {
        self.fetcher = fetcher
        self.deliverUpdate = deliverUpdate
    }

    // MARK: - Public

    /// Whether Upmarket AI is supported for the current device locale.
    var aiSupportedForCurrentLocale: Bool {
        let locale = currentLanguageCode
        return aiSupportedLocales.contains(locale)
    }

    /// Whether AI is coming soon for the current locale (known gap, not random failure).
    var aiComingSoonForCurrentLocale: Bool {
        let locale = currentLanguageCode
        return aiExperimentalLocales.contains(locale)
    }

    /// Full reason string for why AI is unavailable, if it is.
    var aiUnavailableReason: String? {
        let device = DeviceCapability.shared
        if !device.isAppleSilicon {
            return device.upmarketAIUnavailableReason
        }
        if !aiSupportedForCurrentLocale {
            if aiComingSoonForCurrentLocale {
                return "Upmarket AI is coming soon for \(currentLanguageName)"
            }
            return "Upmarket AI is not yet available for \(currentLanguageName)"
        }
        return nil
    }

    /// Combined check: hardware + language both supported.
    var aiAvailable: Bool {
        DeviceCapability.shared.isAppleSilicon && aiSupportedForCurrentLocale
    }

    func fetchFlags() {
        fetcher.fetchFeatureFlags { [weak self] result in
            guard let self, case let .success(payload) = result else { return }
            self.deliverUpdate {
                self.aiSupportedLocales = payload.aiSupportedLocales
                self.aiExperimentalLocales = payload.aiExperimentalLocales
                self.flagsVersion = payload.version
            }
        }
    }

    // MARK: - Private

    private var currentLanguageCode: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    private var currentLanguageName: String {
        Locale.current.localizedString(forLanguageCode: currentLanguageCode)
            ?? currentLanguageCode.uppercased()
    }
}
