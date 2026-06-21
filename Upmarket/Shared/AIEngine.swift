import Foundation

/// The on-device VLM the AI pathway uses. Both run natively on mlx-swift; each is backed by
/// its own downloadable Max-tier weights asset. The user picks one in Preferences; the choice
/// persists in `UserDefaults` under `storageKey` (read by `@AppStorage` in the UI and by
/// `ConversionRunner` via `selected`).
nonisolated enum AIEngine: String, CaseIterable, Codable, Sendable {
    /// Granite-Docling 258M — smaller, fast, narrow (clean typed Latin/Chinese pages).
    case granite
    /// LFM2.5-VL 1.6B — larger, stronger on tables and complex layout, general-purpose.
    case lfm2

    static let storageKey = "upmarket.aiEngine"
    static let `default`: AIEngine = .granite

    /// Engines that have passed native-runtime parity and corpus quality validation.
    static let productionCases: [AIEngine] = [.granite, .lfm2]

    var isProductionAvailable: Bool {
        Self.productionCases.contains(self)
    }

    /// The weights asset this engine loads from disk.
    var asset: ModelAsset {
        switch self {
        case .granite: return .upmarketAI
        case .lfm2:    return .lfm25VL
        }
    }

    /// User-facing label — must not name implementation toolkits (validate_user_facing_copy.py).
    var displayName: String {
        switch self {
        case .granite: return "Fast"
        case .lfm2:    return "Best for Tables"
        }
    }

    /// The engine currently selected by the user (falls back to the default).
    static var selected: AIEngine {
        guard let engine = UserDefaults.standard.string(forKey: storageKey)
            .flatMap(AIEngine.init(rawValue:)),
              engine.isProductionAvailable else {
            return .default
        }
        return engine
    }
}
