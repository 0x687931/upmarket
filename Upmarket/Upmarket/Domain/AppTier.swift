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
/// See docs/TIER_CONTRACT.md for what each asset contains and which tier requires it.
enum ModelAsset: String, CaseIterable, Equatable, Hashable, Sendable {
    case pythonRuntime = "python_runtime_pro"   // Pro tier: ~350MB
    case aiLibraries   = "ai_libraries"         // Max tier: ~750MB
    case upmarketAI    = "upmarket_ai"          // Max tier: ~600MB (model weights)
    case layout        = "layout"               // Enhanced detection: ~20MB

    /// The minimum purchased tier required to download and use this asset.
    var requiredTier: AppTier {
        switch self {
        case .pythonRuntime, .layout: return .pro
        case .aiLibraries, .upmarketAI: return .max
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
        case .layout:                           return .bundledInApp
        case .pythonRuntime,
             .aiLibraries,
             .upmarketAI:                       return .backgroundAssets
        }
    }

    var displayName: String {
        switch self {
        case .pythonRuntime: return "Enhanced Conversions"
        case .aiLibraries:   return "AI Libraries"
        case .upmarketAI:    return "AI for Complex Documents"
        case .layout:        return "Enhanced Model"
        }
    }

    /// Download size (compressed tar.gz file size users will actually download).
    var sizeMB: Int {
        switch self {
        case .pythonRuntime: return 367   // python_runtime_pro.tar.gz actual size
        case .aiLibraries:   return 373   // ai_libraries.tar.gz actual size
        case .upmarketAI:    return 600   // Model weights (estimate)
        case .layout:        return 20
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
        case .ai:       return [.pythonRuntime, .aiLibraries, .upmarketAI]
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
                return "Enhanced conversion requires Upmarket Pro."
            }
            if !deviceSupportsRuntime {
                return "Enhanced conversion requires Apple Silicon."
            }
            let missing = capability.requiredAssets.filter { !downloadedAssets.contains($0) }
            if missing.isEmpty { return nil }
            return "Download \(missing.map(\.displayName).joined(separator: " and ")) to use Enhanced conversion."

        case .ai:
            if tier < .max {
                return "Upmarket AI requires Upmarket Max."
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
            case .pro:   return "Enhanced conversion requires Upmarket Pro."
            case .max:   return "Upmarket AI requires Upmarket Max."
            }
        }
        switch asset {
        case .pythonRuntime, .layout:
            if !deviceSupportsRuntime { return "Enhanced conversion requires Apple Silicon." }
        case .aiLibraries:
            if !deviceSupportsRuntime { return "Upmarket AI requires Apple Silicon." }
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
