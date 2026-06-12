import SwiftUI

enum AppBadgeVariant {
    case accent
    case neutral
    case count
}

struct AppBadge: View {
    let text: String
    let variant: AppBadgeVariant

    init(_ text: String, variant: AppBadgeVariant = .neutral) {
        self.text = text
        self.variant = variant
    }

    var body: some View {
        Text(text)
            .font({
                switch variant {
                case .count:   return .system(size: 10, weight: .semibold, design: .monospaced)
                case .accent:  return .caption2.weight(.heavy)
                case .neutral: return .caption2.weight(.semibold)
                }
            }())
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, variant == .count ? 6 : 6)
            .padding(.vertical, variant == .count ? 1 : 2)
            .background(backgroundStyle, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(borderStyle, lineWidth: variant == .count ? 0.5 : 0)
            )
            .accessibilityHidden(true)
    }

    private var foregroundStyle: AnyShapeStyle {
        switch variant {
        case .accent:
            return AnyShapeStyle(Color.white)
        case .neutral:
            return AnyShapeStyle(Color.secondary)
        case .count:
            return AnyShapeStyle(Color.accentColor)
        }
    }

    private var backgroundStyle: AnyShapeStyle {
        switch variant {
        case .accent:
            return AnyShapeStyle(Color.accentColor)
        case .neutral:
            return AnyShapeStyle(AppTheme.Colour.controlBackground)
        case .count:
            return AnyShapeStyle(AppTheme.Colour.controlBackground)
        }
    }

    private var borderStyle: Color {
        switch variant {
        case .count:
            return AppTheme.Colour.separator
        default:
            return .clear
        }
    }
}
