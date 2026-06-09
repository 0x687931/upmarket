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
        // Compact floating widget (Shelf)
        case shelf
        // Small dialogs and panels
        case thin
        // Main content windows (Workbench, Welcome, Settings)
        case thick

        var contentPadding: CGFloat {
            switch self {
            case .shelf: return Spacing.sm
            case .thin: return Spacing.md
            case .thick: return Spacing.lg
            }
        }

        var itemSpacing: CGFloat {
            switch self {
            case .shelf: return Spacing.xs
            case .thin: return Spacing.sm
            case .thick: return Spacing.md
            }
        }

        var itemPadding: CGFloat {
            switch self {
            case .shelf: return Spacing.sm
            case .thin: return Spacing.md
            case .thick: return Spacing.lg
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .shelf: return Radius.md
            case .thin: return Radius.md
            case .thick: return Radius.lg
            }
        }

        var fontBody: SwiftUI.Font {
            switch self {
            case .shelf: return SwiftUI.Font.caption.weight(.medium)
            case .thin: return SwiftUI.Font.caption.weight(.medium)
            case .thick: return Font.body
            }
        }

        var fontCaption: SwiftUI.Font {
            switch self {
            case .shelf: return SwiftUI.Font.system(size: 9)
            case .thin: return SwiftUI.Font.caption
            case .thick: return Font.caption
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .shelf: return 18
            case .thin: return 20
            case .thick: return 24
            }
        }

        var statusIconSize: CGFloat {
            switch self {
            case .shelf: return 12
            case .thin: return 14
            case .thick: return 16
            }
        }
    }
}
