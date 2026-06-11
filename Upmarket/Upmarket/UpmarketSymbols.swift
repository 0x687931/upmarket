import SwiftUI

/// Centralised SF Symbol system for Upmarket.
///
/// **Usage:** Always use `UpmarketSymbols.xxx` rather than raw `systemName:` strings.
/// This lets us swap symbols, add backwards-compatible exports, and apply
/// consistent rendering modes in one place.
///
/// **Backwards compatibility:**
/// Symbols marked (14+) or (26+) are only available on those OS versions.
/// Exported custom symbols live in Assets.xcassets and are used as fallbacks
/// on earlier OS — use Image(symbol:) extension below, never Image(systemName:) directly.
///
/// **SF Symbols 7.2 features used:**
/// - Variable Draw: symbols that animate by progressive drawing (macOS 14+)
/// - Enhanced Magic Replace: morphing between symbol variants (macOS 14+)
/// - symbolEffect(.pulse/.bounce/.rotate): activity indicators (macOS 14+)
///
/// **To add a new symbol:**
/// 1. Export from SF Symbols 7.2 app: File → Export Symbol (⇧⌘E)
/// 2. Drag SVG into Assets.xcassets
/// 3. Add case here with the asset name as fallback

enum UpmarketSymbols {

    // The app identity mark (Dock + menu bar) is the AppIcon asset itself, not an
    // SF Symbol — the menu bar draws that asset directly so it stays pixel-identical
    // to the Dock icon. See MenuBarStatusIcon in AppDelegate.

    // MARK: - Conversion actions

    /// Drop zone — document with upward arrow
    static let dropZone      = "arrow.down.doc"
    static let dropZoneFill  = "arrow.down.doc.fill"

    /// File being converted — document with sparkle (SF 7.2, exported for 13.3)
    /// Export: "sparkles.rectangle.stack" from SF Symbols 7.2
    static let converting    = "arrow.triangle.2.circlepath"    // system fallback
    static let convertingNew = "sparkles.rectangle.stack"       // SF 7.2, needs export

    /// Conversion complete
    static let done          = "checkmark.circle.fill"
    static let doneDoc       = "text.badge.checkmark"           // SF 7.2, needs export

    /// Conversion failed
    static let failed        = "xmark.circle"
    static let failedFill    = "xmark.circle.fill"

    // MARK: - Document types

    static let pdf           = "doc.richtext"
    static let word          = "doc.text"
    static let powerpoint    = "rectangle.on.rectangle"
    static let excel         = "tablecells"
    static let html          = "globe"
    static let image         = "photo"
    static let audio         = "waveform"                       // for audio files
    static let video         = "film"

    // MARK: - AI / Pro features

    /// Upmarket AI — sparkles is the right symbol
    static let ai            = "sparkles"
    static let aiDocument    = "sparkles.rectangle.stack"       // SF 7.2, needs export
    static let proFeature    = "sparkles"

    // MARK: - Actions

    static let copy          = "doc.on.doc"
    static let save          = "square.and.arrow.down"
    static let share         = "square.and.arrow.up"
    static let openFile      = "folder"
    static let newConversion = "plus"
    static let delete        = "trash"
    static let close         = "xmark"
    static let expand        = "arrow.up.left.and.arrow.down.right"
    static let collapse      = "arrow.down.right.and.arrow.up.left"

    // MARK: - Status

    static let downloading   = "arrow.down.circle"
    static let downloadDone  = "checkmark.circle.fill"
    static let warning       = "exclamationmark.triangle"
    static let warningFill   = "exclamationmark.triangle.fill"
    static let info          = "info.circle"
    static let lock          = "lock.doc"
    static let offline       = "wifi.slash"

    // MARK: - Preferences tabs

    static let prefModels    = "cpu"
    static let prefAccount   = "person.circle"
    static let prefAbout     = "info.circle"
    static let prefGeneral   = "gearshape"

    // MARK: - Shelf

    static let shelfDropIdle    = "arrow.down.circle"
    static let shelfDropActive  = "arrow.down.circle.fill"
    static let shelfExpand      = "arrow.up.backward.and.arrow.down.forward"

    // MARK: - Language / AI availability

    static let languageWarning  = "exclamationmark.bubble"
    static let comingSoon       = "clock.badge.questionmark"    // SF 7.2

    // MARK: - Onboarding

    static let welcome          = "number"                      // use Text("#") for this
    static let onboardDrop      = "arrow.down.doc"
    static let onboardAI        = "cpu.fill"
    static let onboardReady     = "checkmark.seal.fill"
}

// MARK: - Exported symbol names (SVG in Assets.xcassets, work on macOS 13.3+)
// These were exported from SF Symbols 7.2 and added to Assets.xcassets.
// Use Image(exported:) to get them — falls back to system symbol on newer OS.

private let exportedSymbols: Set<String> = [
    "sparkles.rectangle.stack",
    "text.badge.checkmark",
    "clock.badge.questionmark",
]

// MARK: - SwiftUI Image extension

extension Image {

    /// Create an image using a symbol from UpmarketSymbols.
    /// - For symbols exported to Assets.xcassets: uses asset on all OS versions
    /// - For system symbols: uses systemName
    /// Usage: Image(symbol: UpmarketSymbols.aiDocument)
    init(symbol name: String) {
        if exportedSymbols.contains(name) {
            // Use asset catalogue export — works back to macOS 13.3
            self = Image(name)
        } else {
            self = Image(systemName: name)
        }
    }

    /// Apply standard Upmarket rendering to a symbol image.
    /// Hierarchical mode gives depth to filled/unfilled variants.
    func upmarketStyle(_ color: Color = .accentColor) -> some View {
        self
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
    }
}

// MARK: - Animated symbol helper (macOS 14+)

@ViewBuilder
func UpmarketAnimatedSymbol(
    _ name: String,
    isActive: Bool = false,
    color: Color = .accentColor
) -> some View {
    if #available(macOS 14.0, *) {
        Image(systemName: name)
            .foregroundStyle(color)
            .symbolEffect(.pulse, isActive: isActive)
            .symbolEffect(.bounce, value: isActive)
    } else {
        Image(systemName: name)
            .foregroundStyle(color)
    }
}

// MARK: - Variable Draw progress symbol (macOS 15+)

/// A symbol that fills progressively as value increases 0.0→1.0
/// Uses Variable Color on macOS 15+, falls back to static symbol
@ViewBuilder
func UpmarketProgressSymbol(
    _ name: String,
    value: Double,
    color: Color = .accentColor
) -> some View {
    if #available(macOS 15.0, *) {
        Image(systemName: name, variableValue: value)
            .foregroundStyle(color)
    } else {
        Image(systemName: name)
            .foregroundStyle(color.opacity(0.5 + value * 0.5))
    }
}
