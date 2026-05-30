import Foundation
import Combine

/// Remote feature flags fetched at launch.
/// Controls which UI locales support Upmarket AI without requiring an app update.
/// Falls back to a conservative hardcoded allowlist if fetch fails.
final class FeatureFlags: ObservableObject {

    static let shared = FeatureFlags()

    // Hosted on GitHub Pages — update this file to enable new languages instantly
    private static let flagsURL = "https://0x687931.github.io/upmarket/flags.json"

    // Conservative fallback — Latin-script languages only
    private static let fallbackSupportedLocales: Set<String> = [
        "en", "fr", "de", "es", "it", "pt", "nl",
        "pl", "sv", "da", "no", "fi", "ru", "cs",
        "sk", "hu", "ro", "hr", "bg", "uk"
    ]

    // Languages where AI is known not to work well yet
    private static let knownUnsupportedLocales: Set<String> = [
        "zh", "ja", "ko", "ar", "he", "hi", "th", "vi"
    ]

    let objectWillChange = PassthroughSubject<Void, Never>()

    private(set) var aiSupportedLocales: Set<String> = fallbackSupportedLocales {
        willSet { objectWillChange.send() }
    }

    private(set) var aiExperimentalLocales: Set<String> = knownUnsupportedLocales {
        willSet { objectWillChange.send() }
    }

    private(set) var flagsVersion: Int = 0

    private init() {}

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
        guard let url = URL(string: Self.flagsURL) else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self, let data, error == nil else { return }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            let supported   = (json["ai_supported_locales"] as? [String]).map(Set.init) ?? Self.fallbackSupportedLocales
            let experimental = (json["ai_experimental_locales"] as? [String]).map(Set.init) ?? Self.knownUnsupportedLocales
            let version     = json["version"] as? Int ?? 0

            DispatchQueue.main.async {
                self.aiSupportedLocales     = supported
                self.aiExperimentalLocales  = experimental
                self.flagsVersion           = version
            }
        }.resume()
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
