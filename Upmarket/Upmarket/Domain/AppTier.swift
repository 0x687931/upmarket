import Foundation

// MARK: - AppTier

/// The user's license tier. Basic is the default — no purchase required.
/// All feature gating derives from this type.
enum AppTier: Int, Comparable, Equatable, Sendable {
    case basic = 0  // default — native Apple API conversion, no purchase
    case pro   = 1  // $9.99  — enhanced Docling conversion (layout + table OCR)
    case max   = 2  // $14.99 — AI/VLM conversion (Granite Docling MLX)

    static func < (lhs: AppTier, rhs: AppTier) -> Bool { lhs.rawValue < rhs.rawValue }

    var displayName: String {
        switch self {
        case .basic: return "Upmarket Basic"
        case .pro:   return "Upmarket Pro"
        case .max:   return "Upmarket Max"
        }
    }

    var price: String {
        switch self {
        case .basic: return "Free"
        case .pro:   return "$9.99"
        case .max:   return "$14.99"
        }
    }

    /// StoreKit non-consumable product identifier. Nil for Basic (no purchase needed).
    var productID: String? {
        switch self {
        case .basic: return nil
        case .pro:   return "com.upmarket.app.pro"
        case .max:   return "com.upmarket.app.max"
        }
    }
}

// MARK: - ModelAsset

/// Every binary asset that must be present on disk for a conversion capability to function.
/// Raw values match the Python model_manager.py MODELS dict keys exactly.
enum ModelAsset: String, CaseIterable, Equatable, Hashable, Sendable {
    case pythonRuntime = "python_runtime"
    case layout        = "layout"
    case upmarketAI    = "upmarket_ai"

    /// The minimum purchased tier required to download and use this asset.
    var requiredTier: AppTier {
        switch self {
        case .pythonRuntime, .layout: return .pro
        case .upmarketAI:             return .max
        }
    }

    /// How the asset is delivered to the user's machine.
    enum Delivery: Sendable {
        /// Copied from the .app bundle at first launch — always present after install.
        case bundledInApp
        /// Delivered by Apple Background Assets on App Store; GitHub CDN in debug builds.
        case backgroundAssets
    }

    var delivery: Delivery {
        switch self {
        case .layout:                return .bundledInApp
        case .pythonRuntime,
             .upmarketAI:           return .backgroundAssets
        }
    }

    var displayName: String {
        switch self {
        case .pythonRuntime: return "Upmarket Runtime"
        case .layout:        return "Enhanced Model"
        case .upmarketAI:    return "Upmarket AI Model"
        }
    }

    /// Approximate on-disk size for display purposes.
    var sizeMB: Int {
        switch self {
        case .pythonRuntime: return 1300
        case .layout:        return 300
        case .upmarketAI:    return 618
        }
    }
}

// MARK: - ConversionCapability

/// A conversion quality level. Each capability maps to a required tier and the
/// assets that must be present on disk before it can run.
enum ConversionCapability: Equatable, Sendable {
    /// Apple-native only: PDFKit, Vision OCR, Speech, AVFoundation. Always available.
    case native
    /// Docling layout + table pipeline. Requires Pro tier + python_runtime + layout.
    case enhanced
    /// Granite Docling VLM pipeline. Requires Max tier + python_runtime + upmarket_ai.
    case ai

    var requiredTier: AppTier {
        switch self {
        case .native:   return .basic
        case .enhanced: return .pro
        case .ai:       return .max
        }
    }

    /// All assets that must be on disk before this capability can run.
    var requiredAssets: [ModelAsset] {
        switch self {
        case .native:   return []
        case .enhanced: return [.pythonRuntime, .layout]
        case .ai:       return [.pythonRuntime, .upmarketAI]
        }
    }

    var displayName: String {
        switch self {
        case .native:   return "Standard"
        case .enhanced: return "Enhanced"
        case .ai:       return "AI"
        }
    }

    var diagnosticLabel: String { displayName }
}

// MARK: - AppTierGate

/// The single point of truth for all capability and download gating decisions.
///
/// Construct one from the current store tier + downloaded assets and call
/// `unavailableReason(for:)` or `downloadUnavailableReason(for:)`. A nil return
/// means the action is permitted; a non-nil string is user-visible copy.
struct AppTierGate: Sendable {

    let tier: AppTier
    let downloadedAssets: Set<ModelAsset>
    let deviceSupportsRuntime: Bool
    let aiFeatureEnabled: Bool
    let aiFeatureUnavailableReason: String?

    // MARK: Capability gating

    /// Returns nil if the user can use `capability` right now, otherwise a user-visible reason.
    func unavailableReason(for capability: ConversionCapability) -> String? {
        switch capability {
        case .native:
            return nil

        case .enhanced:
            if tier < .pro {
                return "Enhanced conversion requires Upmarket Pro (\(AppTier.pro.price))."
            }
            if !deviceSupportsRuntime {
                return "Enhanced conversion requires Apple Silicon."
            }
            let missing = capability.requiredAssets.filter { !downloadedAssets.contains($0) }
            if missing.isEmpty { return nil }
            return "Download \(missing.map(\.displayName).joined(separator: " and ")) to use Enhanced conversion."

        case .ai:
            if tier < .max {
                return "Upmarket AI requires Upmarket Max (\(AppTier.max.price))."
            }
            if !deviceSupportsRuntime {
                return "Upmarket AI requires Apple Silicon."
            }
            if !aiFeatureEnabled {
                return aiFeatureUnavailableReason ?? "Upmarket AI is not available for this Mac or language yet."
            }
            let missing = capability.requiredAssets.filter { !downloadedAssets.contains($0) }
            if missing.isEmpty { return nil }
            return "Download \(missing.map(\.displayName).joined(separator: " and ")) to use Upmarket AI."
        }
    }

    /// True if the user can use `capability` right now.
    func canUse(_ capability: ConversionCapability) -> Bool {
        unavailableReason(for: capability) == nil
    }

    // MARK: Download gating

    /// Returns nil if the user can download `asset`, otherwise a user-visible reason.
    func downloadUnavailableReason(for asset: ModelAsset) -> String? {
        if tier < asset.requiredTier {
            switch asset.requiredTier {
            case .basic: return nil
            case .pro:   return "Enhanced conversion requires Upmarket Pro (\(AppTier.pro.price))."
            case .max:   return "Upmarket AI requires Upmarket Max (\(AppTier.max.price))."
            }
        }
        switch asset {
        case .pythonRuntime, .layout:
            if !deviceSupportsRuntime { return "Enhanced conversion requires Apple Silicon." }
        case .upmarketAI:
            if !deviceSupportsRuntime { return "Upmarket AI requires Apple Silicon." }
            if !aiFeatureEnabled {
                return aiFeatureUnavailableReason ?? "Upmarket AI is not available for this Mac or language yet."
            }
        }
        return nil
    }

    /// True if the user can download `asset`.
    func canDownload(_ asset: ModelAsset) -> Bool {
        downloadUnavailableReason(for: asset) == nil
    }

    // MARK: Convenience

    /// Returns the assets for `capability` that are permitted to download but not yet present.
    func missingDownloadableAssets(for capability: ConversionCapability) -> [ModelAsset] {
        capability.requiredAssets.filter { !downloadedAssets.contains($0) && canDownload($0) }
    }
}
