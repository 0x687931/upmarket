import Foundation

// MARK: - AppTier

/// The user's license tier. Basic is the default — no purchase required.
/// All feature gating derives from this type.
enum AppTier: Int, Comparable, Equatable, Sendable {
    case basic = 0  // A$4.99 — everyday documents (native + MarkItDown core)
    case pro   = 1  // A$14.99 — spreadsheets, audio, complex PDF, batch, CLI/MCP
    case max   = 2  // A$49.99 — AI/VLM reconstruction (Granite Docling MLX)

    static func < (lhs: AppTier, rhs: AppTier) -> Bool { lhs.rawValue < rhs.rawValue }

    // StoreKit non-consumable product identifiers — the single source of truth.
    // Store.storekit and App Store Connect must match (enforced by AppTierContractTests).
    // There is no free tier product: the app is free to download with a 5-conversion
    // trial (tracked in StoreManager), after which a tier must be purchased.
    static let basicProductID = "com.upmarket.app.basic"
    static let proProductID   = "com.upmarket.app.pro"
    static let maxProductID   = "com.upmarket.app.max"

    var displayName: String {
        switch self {
        case .basic: return "Upmarket Basic"
        case .pro:   return "Upmarket Pro"
        case .max:   return "Upmarket Max"
        }
    }

    var price: String {
        switch self {
        case .basic: return "A$4.99"
        case .pro:   return "A$14.99"
        case .max:   return "A$49.99"
        }
    }

    /// StoreKit non-consumable product identifier. Every tier is purchasable.
    var productID: String {
        switch self {
        case .basic: return Self.basicProductID
        case .pro:   return Self.proProductID
        case .max:   return Self.maxProductID
        }
    }

    /// Document-type → minimum tier (the upgrade-funnel contract). PDF is `basic` at the
    /// format level; PDF *complexity* (scanned=basic, complex layout=pro, AI=max) is
    /// layered on by ConversionCapability. Enforced by AppTierContractTests.
    static func requiredTier(for format: ConversionFormat) -> AppTier {
        switch format {
        case .xlsx, .pptx, .xls, .ppt, .epub, .mp3, .m4a, .wav, .aiff,
             .json, .xml, .zip, .webvtt, .asciidoc:
            // Spreadsheets, presentations, ebooks, and audio are Pro features (EPUB converts
            // natively, like XLSX/PPTX, but stays a Pro format); structured formats with no
            // native engine (JSON/XML/ZIP/WEBVTT) also require the advanced runtime.
            return .pro
        default:
            // Documents (DOC/DOCX), text (TXT/MD/CSV), HTML, images, digital/scanned PDF —
            // all served by in-process native engines, so the Basic tier needs no Python.
            return .basic
        }
    }
}

// MARK: - ModelAsset

/// Every binary asset that must be present on disk for a conversion capability to function.
/// Only the Max-tier AI model remains a download: all other engines are native (PDFKit,
/// Vision, Speech, AVFoundation, SwiftOfficeMarkdown), so Basic and Pro need no assets.
/// See docs/TIER_CONTRACT.md for what each asset contains and which tier requires it.
enum ModelAsset: String, CaseIterable, Equatable, Hashable, Sendable {
    case graniteDocling = "granite_docling"   // Max tier: ~600MB (Granite-Docling mlx-swift weights)
    case lfm25VL    = "lfm25_vl"      // Max tier: ~2.0GB (LFM2.5-VL 1.6B 8-bit mlx-swift weights)

    /// The minimum purchased tier required to download and use this asset.
    var requiredTier: AppTier {
        switch self {
        case .graniteDocling, .lfm25VL: return .max
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
        case .graniteDocling, .lfm25VL: return .backgroundAssets
        }
    }

    /// Apple-hosted managed Background Assets pack identifier (Release/TestFlight delivery).
    /// Must match the assetPackID in resources/asset-packs/*.json and App Store Connect.
    var assetPackID: String {
        switch self {
        case .graniteDocling: return "com.upmarket.app.models.granite"
        case .lfm25VL:    return "com.upmarket.app.models.lfm25-vl"
        }
    }

    var displayName: String {
        switch self {
        case .graniteDocling: return "AI for Complex Documents"
        case .lfm25VL:    return "Advanced AI for Tables & Layout"
        }
    }

    /// Download size (compressed archive file size users will actually download).
    var sizeMB: Int {
        switch self {
        case .graniteDocling: return 600    // Model weights (estimate)
        case .lfm25VL:    return 2000   // 1.6B 8-bit weights (estimate)
        }
    }
}

// MARK: - ConversionCapability

/// A conversion quality level. Each capability maps to a required tier and the
/// assets that must be present on disk before it can run.
enum ConversionCapability: Equatable, Sendable {
    /// Apple-native only: PDFKit, Vision OCR, Speech, AVFoundation. Always available.
    case native
    /// Native complex-document path (PDFKit + Vision quality selection, SwiftOfficeMarkdown).
    /// Requires Pro tier; no download.
    case enhanced
    /// Granite-Docling VLM (mlx-swift, native). Requires Max tier + granite_docling weights.
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
        case .enhanced: return []
        case .ai:       return [.graniteDocling]
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
            // Enhanced converts natively (SwiftOfficeMarkdown, NativeEPUBConverter, Vision)
            // and runs on Intel as well as Apple Silicon, so it gates on tier only.
            if tier < .pro {
                return "Enhanced conversion requires Upmarket Pro."
            }
            return nil

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
        case .graniteDocling, .lfm25VL:
            // Both AI engines run on mlx-swift and share the same device/feature gating.
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
