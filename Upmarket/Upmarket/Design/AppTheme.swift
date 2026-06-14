import SwiftUI
import AppKit

enum AppTheme {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let menuBar: CGFloat = 5
        static let pill: CGFloat = 999
        // App-icon squircle ≈ 21.5% of side — matches --radius-app-icon
        static let appIcon: CGFloat = 14      // 21.5% × 64px (Paywall icon)
        static let appIconLarge: CGFloat = 18 // 21.5% × 84px (Welcome icon)
    }

    enum Size {
        static let dropZoneHeight: CGFloat = 160
        static let fileIconBox: CGFloat = 40
        static let fileIcon: CGFloat = 24
        static let actionIcon: CGFloat = 11
        static let statusIcon: CGFloat = 16
        static let chooseButtonWidth: CGFloat = 140
        static let appIconSize: CGFloat = 96
        static let featureIconBox: CGFloat = 44
        static let featureIcon: CGFloat = 20
        static let menuBarIcon: CGFloat = 22
        static let arcRing: CGFloat = 46
        static let strokeRing: CGFloat = 3
        static let strokeRingThin: CGFloat = 2.5
    }

    enum Font {
        static let title = SwiftUI.Font.headline.weight(.semibold)
        static let body = SwiftUI.Font.subheadline.weight(.medium)
        static let caption = SwiftUI.Font.caption
        static let captionStrong = SwiftUI.Font.caption.weight(.medium)
        static let largeTitle = SwiftUI.Font.largeTitle.weight(.bold)
        static let title3 = SwiftUI.Font.title3
        static let title2 = SwiftUI.Font.title2
        static let sectionLabel = SwiftUI.Font.caption2.weight(.semibold)

        // Hero numerals / "#" mark — SF Pro Rounded
        static let heroRounded = SwiftUI.Font.system(.largeTitle, design: .rounded).weight(.bold)
        // Markdown output / shortcuts — SF Mono
        static let mono = SwiftUI.Font.system(.caption, design: .monospaced)
    }

    enum Colour {
        static let background = Color(nsColor: .windowBackgroundColor)
        static let surface = Color(nsColor: .controlBackgroundColor)           // --surface: white (light) / dark card
        static let controlBackground = Color(nsColor: .controlBackgroundColor)
        static let subtleFill = Color.secondary.opacity(0.04)
        static let selectedFill = Color.accentColor.opacity(0.06)
        static let dropFill = Color.accentColor.opacity(0.04)
        static let dropFillActive = Color.accentColor.opacity(0.08)
        static let border = Color.secondary.opacity(0.2)
        static let separator = Color.primary.opacity(0.10)
        static let borderActive = Color.accentColor

        static let success = Color(red: 0.204, green: 0.780, blue: 0.349) // #34C759
        static let warning = Color(red: 1.0,   green: 0.624, blue: 0.039) // #FF9F0A
        static let error   = Color(red: 1.0,   green: 0.216, blue: 0.373) // #FF375F
        static let info    = Color(red: 0.369, green: 0.361, blue: 0.902) // #5E5CE6

        static let iconBoxFill = Color.blue.opacity(0.12)
        static let iconGlyphTint = Color(red: 0.184, green: 0.498, blue: 1.0) // #2F7FFF — file-icon glyph
        static let tintError = error.opacity(0.05) // banner background for "trial ended"

        // --text-tertiary: rgba(0,0,0,0.26) light / rgba(255,255,255,0.30) dark
        static let textTertiary = Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.30)
                : NSColor.black.withAlphaComponent(0.26)
        })

        // --fill-track: rgba(0,0,0,0.10) light / rgba(255,255,255,0.12) dark
        static let arcTrack = Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.12)
                : NSColor.black.withAlphaComponent(0.10)
        })

        // --- Accent tints (rgb of #E86E00 = 232,110,0) -----------
        static let accentTint04 = Color.accentColor.opacity(0.04) // drop-zone idle
        static let accentTint06 = Color.accentColor.opacity(0.06) // selected row
        static let accentTint08 = Color.accentColor.opacity(0.08) // drop-zone active
        static let accentTint10 = Color.accentColor.opacity(0.10) // primary-row hover
        static let accentTint15 = Color.accentColor.opacity(0.15) // pressed / ghost
        static let accentTint25 = Color.accentColor.opacity(0.25) // converting glow bloom

        // --- Brand gradient (5-stop amber -> orange ramp) --------
        static let brandStop1 = Color(red: 1.000, green: 0.749, blue: 0.251) // #FFBF40
        static let brandStop2 = Color(red: 1.000, green: 0.761, blue: 0.165) // #FFC22A
        static let brandStop3 = Color(red: 1.000, green: 0.702, blue: 0.082) // #FFB315
        static let brandStop4 = Color(red: 0.996, green: 0.639, blue: 0.0)   // #FEA300
        static let brandStop5 = Color(red: 0.910, green: 0.431, blue: 0.0)   // #E86E00 (accent)

        // Stop locations are uneven (0.72 not 0.75) per the DS-3 handoff ramp.
        static let brandGradient = LinearGradient(
            stops: [
                .init(color: brandStop1, location: 0.00),
                .init(color: brandStop2, location: 0.25),
                .init(color: brandStop3, location: 0.50),
                .init(color: brandStop4, location: 0.72),
                .init(color: brandStop5, location: 1.00),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        // --- Section accent palette (DS-3 README) -----------------
        // Per-section icon squares, plan card, and report categories.
        // Distinct from the semantic status tokens above.
        static let sectionBlue   = iconGlyphTint                                  // #2F7FFF
        static let sectionPurple = Color(red: 0.369, green: 0.361, blue: 0.902)   // #5E5CE6
        static let sectionAmber  = Color(red: 1.0,   green: 0.624, blue: 0.039)   // #FF9F0A
        static let sectionRed    = Color(red: 1.0,   green: 0.216, blue: 0.373)   // #FF375F
        static let sectionGreen  = success                                        // #34C759

        // --- Warm shadow / shelf bloom ---------------------------
        static let amberShadow = Color(red: 0.478, green: 0.227, blue: 0.0) // #7A3A00
        static let shelfBloomShadow = Color(red: 0.478, green: 0.227, blue: 0.0).opacity(0.30)

        // DS glass fills are explicit translucent surfaces, not native AppKit material recipes.
        static let glassFill = controlBackground.opacity(0.62)
        static let glassFillThin = controlBackground.opacity(0.50)
        static let glassStroke = Color.white.opacity(0.55)

        // --- Traffic-light / window chrome controls -----------
        static let trafficRed    = Color(red: 1.0,   green: 0.373, blue: 0.341) // #ff5f57
        static let trafficYellow = Color(red: 0.996, green: 0.737, blue: 0.180) // #febc2e
        static let trafficGreen  = Color(red: 0.157, green: 0.784, blue: 0.251) // #28c840

        // --- Shelf control strip --------------------------------
        static let shelfHoverClose  = trafficRed
        static let shelfHoverAdd    = trafficGreen
        static let shelfHoverToggle = iconGlyphTint                              // #2f7fff
        static let shelfControlStripFill = Color.white.opacity(0.25)

        // --- Shelf cards ------------------------------------------
        static let shelfCardFill = Color.white.opacity(0.5) // ShelfCard background
        static let shelfOverflowFill = Color.white.opacity(0.55) // Overflow stack cards
    }

    enum Status {
        static let complete = Colour.success
        static let failed = Colour.error
        static let processing = Color.accentColor
        static let queued = Color.secondary.opacity(0.30)
    }

    // MARK: - Window Size Variants

    enum WindowSize {
        // Primary Upmarket workbench window (conversions + history)
        case main
        // Modal dialogs and secondary windows
        case modal
        // Compact floating widget (Shelf)
        case compact
        // Welcome/onboarding window
        case welcome
        // Preferences window (wider, scrollable)
        case preferences

        var contentPadding: CGFloat {
            switch self {
            case .main: return Spacing.sm
            case .modal: return Spacing.md
            case .compact: return Spacing.sm
            case .welcome: return Spacing.lg
            case .preferences: return Spacing.xl
            }
        }

        var itemSpacing: CGFloat {
            switch self {
            case .main: return Spacing.xs
            case .modal: return Spacing.sm
            case .compact: return Spacing.xs
            case .welcome: return Spacing.lg
            case .preferences: return Spacing.lg
            }
        }

        var itemPadding: CGFloat {
            switch self {
            case .main: return Spacing.sm
            case .modal: return Spacing.md
            case .compact: return Spacing.sm
            case .welcome: return Spacing.lg
            case .preferences: return Spacing.md
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .main: return Radius.md
            case .modal: return Radius.md
            case .compact: return Radius.md
            case .welcome: return Radius.md
            case .preferences: return Radius.md
            }
        }

        var fontBody: SwiftUI.Font {
            switch self {
            case .main: return SwiftUI.Font.caption.weight(.medium)
            case .modal: return SwiftUI.Font.caption.weight(.medium)
            case .compact: return SwiftUI.Font.caption.weight(.medium)
            case .welcome: return Font.body
            case .preferences: return Font.body
            }
        }

        var fontCaption: SwiftUI.Font {
            switch self {
            case .main: return SwiftUI.Font.system(size: 9)
            case .modal: return SwiftUI.Font.caption
            case .compact: return SwiftUI.Font.system(size: 9)
            case .welcome: return Font.caption
            case .preferences: return Font.caption
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .main: return 18
            case .modal: return 20
            case .compact: return 18
            case .welcome: return 24
            case .preferences: return 20
            }
        }

        var statusIconSize: CGFloat {
            switch self {
            case .main: return 12
            case .modal: return 14
            case .compact: return 12
            case .welcome: return 16
            case .preferences: return 14
            }
        }

        var width: CGFloat {
            switch self {
            case .main: return 480        // Primary Upmarket workbench
            case .modal: return 480       // Modal dialogs
            case .compact: return 217     // Shelf floating widget
            case .welcome: return 520     // Welcome/onboarding
            case .preferences: return 600 // Preferences (wider, icon-led sections)
            }
        }

        var height: CGFloat {
            switch self {
            case .main: return 560        // Upmarket workbench
            case .modal: return 600       // Modal dialogs
            case .compact: return 132     // Shelf widget
            case .welcome: return 540     // Welcome/onboarding window
            case .preferences: return 520 // Preferences initial height (resizable)
            }
        }
    }
}
