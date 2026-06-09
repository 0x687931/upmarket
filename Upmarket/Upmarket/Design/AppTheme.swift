import SwiftUI

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
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
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
    }

    enum Font {
        static let title = SwiftUI.Font.headline.weight(.semibold)
        static let body = SwiftUI.Font.subheadline.weight(.medium)
        static let caption = SwiftUI.Font.caption
        static let captionStrong = SwiftUI.Font.caption.weight(.medium)
        static let largeTitle = SwiftUI.Font.largeTitle.weight(.bold)
        static let title3 = SwiftUI.Font.title3
    }

    enum Colour {
        static let background = Color(nsColor: .windowBackgroundColor)
        static let controlBackground = Color(nsColor: .controlBackgroundColor)
        static let subtleFill = Color.secondary.opacity(0.04)
        static let selectedFill = Color.accentColor.opacity(0.06)
        static let dropFill = Color.accentColor.opacity(0.04)
        static let dropFillActive = Color.accentColor.opacity(0.08)
        static let border = Color.secondary.opacity(0.2)
        static let borderActive = Color.accentColor

        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        static let info = Color.accentColor

        static let iconBoxFill = Color.blue.opacity(0.12)
    }

    enum Status {
        static let complete = Color.green
        static let failed = Color.red
        static let processing = Color.accentColor
        static let queued = Color.secondary.opacity(0.5)
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

        var contentPadding: CGFloat {
            switch self {
            case .main: return Spacing.sm
            case .modal: return Spacing.md
            case .compact: return Spacing.sm
            case .welcome: return Spacing.lg
            }
        }

        var itemSpacing: CGFloat {
            switch self {
            case .main: return Spacing.xs
            case .modal: return Spacing.sm
            case .compact: return Spacing.xs
            case .welcome: return Spacing.lg
            }
        }

        var itemPadding: CGFloat {
            switch self {
            case .main: return Spacing.sm
            case .modal: return Spacing.md
            case .compact: return Spacing.sm
            case .welcome: return Spacing.lg
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .main: return Radius.md
            case .modal: return Radius.md
            case .compact: return Radius.md
            case .welcome: return Radius.lg
            }
        }

        var fontBody: SwiftUI.Font {
            switch self {
            case .main: return SwiftUI.Font.caption.weight(.medium)
            case .modal: return SwiftUI.Font.caption.weight(.medium)
            case .compact: return SwiftUI.Font.caption.weight(.medium)
            case .welcome: return Font.body
            }
        }

        var fontCaption: SwiftUI.Font {
            switch self {
            case .main: return SwiftUI.Font.system(size: 9)
            case .modal: return SwiftUI.Font.caption
            case .compact: return SwiftUI.Font.system(size: 9)
            case .welcome: return Font.caption
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .main: return 18
            case .modal: return 20
            case .compact: return 18
            case .welcome: return 24
            }
        }

        var statusIconSize: CGFloat {
            switch self {
            case .main: return 12
            case .modal: return 14
            case .compact: return 12
            case .welcome: return 16
            }
        }

        var width: CGFloat {
            switch self {
            case .main: return 420        // Primary Upmarket workbench
            case .modal: return 480       // Modal dialogs
            case .compact: return 217     // Shelf floating widget
            case .welcome: return 520     // Welcome/onboarding
            }
        }

        var height: CGFloat {
            switch self {
            case .main: return 560        // Upmarket workbench
            case .modal: return 600       // Modal dialogs
            case .compact: return 132     // Shelf widget
            case .welcome: return 460     // Welcome window
            }
        }
    }
}
