import SwiftUI

struct AppProminentButtonStyle: ButtonStyle {
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        let metrics = Self.metrics(for: controlSize)

        configuration.label
            .font(.system(size: metrics.fontSize, weight: .semibold))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.94 : 1))
            .padding(.vertical, metrics.verticalPadding)
            .padding(.horizontal, metrics.horizontalPadding)
            .frame(minHeight: metrics.minHeight)
            .background(
                RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.88 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(configuration.isPressed ? 0.18 : 0.08), lineWidth: 0.5)
            )
            .opacity(configuration.isPressed ? 0.96 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .contentShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
    }

    private static func metrics(for controlSize: ControlSize) -> (fontSize: CGFloat, verticalPadding: CGFloat, horizontalPadding: CGFloat, minHeight: CGFloat, cornerRadius: CGFloat) {
        switch controlSize {
        case .mini:
            return (10, 4, 8, 20, 5)
        case .small:
            return (11, 5, 12, 24, 6)
        case .regular:
            return (13, 6, 16, 28, AppTheme.Radius.sm)
        case .large:
            return (13, 9, 20, 36, AppTheme.Radius.md)
        case .extraLarge:
            return (13, 9, 20, 36, AppTheme.Radius.md)
        @unknown default:
            return (13, 6, 16, 28, AppTheme.Radius.sm)
        }
    }
}

struct AppBorderedButtonStyle: ButtonStyle {
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        let metrics = Self.metrics(for: controlSize)

        configuration.label
            .font(.system(size: metrics.fontSize, weight: .medium))
            .foregroundStyle(.primary.opacity(configuration.isPressed ? 0.96 : 0.88))
            .padding(.vertical, metrics.verticalPadding)
            .padding(.horizontal, metrics.horizontalPadding)
            .frame(minHeight: metrics.minHeight)
            .background(
                RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                    .fill(AppTheme.Colour.controlBackground.opacity(configuration.isPressed ? 0.8 : 0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                    .strokeBorder(AppTheme.Colour.border.opacity(configuration.isPressed ? 0.4 : 0.28), lineWidth: 0.5)
            )
            .opacity(configuration.isPressed ? 0.98 : 1)
            .scaleEffect(configuration.isPressed ? 0.988 : 1)
            .contentShape(RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous))
    }

    private static func metrics(for controlSize: ControlSize) -> (fontSize: CGFloat, verticalPadding: CGFloat, horizontalPadding: CGFloat, minHeight: CGFloat, cornerRadius: CGFloat) {
        switch controlSize {
        case .mini:
            return (10, 3, 8, 20, 5)
        case .small:
            return (11, 4, 12, 24, 6)
        case .regular:
            return (13, 6, 16, 28, AppTheme.Radius.sm)
        case .large:
            return (13, 9, 20, 36, AppTheme.Radius.md)
        case .extraLarge:
            return (13, 9, 20, 36, AppTheme.Radius.md)
        @unknown default:
            return (13, 6, 16, 28, AppTheme.Radius.sm)
        }
    }
}

struct AppPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.Font.body.weight(.medium))
            .foregroundStyle(Color.accentColor.opacity(configuration.isPressed ? 0.82 : 1))
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

struct AppSubtleRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(AppTheme.Colour.controlBackground.opacity(configuration.isPressed ? 0.8 : 0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .strokeBorder(AppTheme.Colour.border.opacity(configuration.isPressed ? 0.42 : 0.28), lineWidth: 0.5)
            )
            .opacity(configuration.isPressed ? 0.98 : 1)
            .scaleEffect(configuration.isPressed ? 0.995 : 1)
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
    }
}

struct AppActionButtonStyle: ButtonStyle {
    enum Size {
        case regular
        case compact
    }

    let size: Size

    init(size: Size = .regular) {
        self.size = size
    }

    func makeBody(configuration: Configuration) -> some View {
        let metrics = Self.metrics(for: size)

        configuration.label
            .font(.system(size: metrics.fontSize, weight: .semibold))
            .foregroundStyle(.primary.opacity(configuration.isPressed ? 0.95 : 0.78))
            .padding(metrics.padding)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    .fill(AppTheme.Colour.glassFillThin.opacity(configuration.isPressed ? 0.72 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    .strokeBorder(AppTheme.Colour.border, lineWidth: 0.5)
            )
            .opacity(configuration.isPressed ? 1 : 0.82)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
    }

    private static func metrics(for size: Size) -> (fontSize: CGFloat, padding: CGFloat) {
        switch size {
        case .regular:
            // box = size + 10 (5pt padding each side) — matches DS ActionIconButton
            return (AppTheme.Size.actionIcon, 5)
        case .compact:
            // box = size + 10 (5pt padding each side) — matches DS ActionIconButton
            return (9, 5)
        }
    }
}

enum AppCardVariant {
    case subtle
    case outlined
    case hero
    case glass
}

struct AppCardStyle: ButtonStyle {
    let variant: AppCardVariant
    let isSelected: Bool
    let isDisabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed

        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, 14)
            .background(background)
            .overlay(border)
            .opacity(isDisabled ? 0.6 : (pressed ? 0.98 : 1))
            .scaleEffect(pressed ? 0.995 : 1)
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
            .fill(backgroundFill)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
            .strokeBorder(borderColor, lineWidth: borderWidth)
    }

    private var backgroundFill: Color {
        switch variant {
        case .subtle:
            return isSelected ? AppTheme.Colour.selectedFill : AppTheme.Colour.subtleFill
        case .outlined:
            return Color.clear
        case .hero:
            return isSelected ? AppTheme.Colour.accentTint06 : Color.clear
        case .glass:
            return AppTheme.Colour.controlBackground.opacity(isSelected ? 0.75 : 0.6)
        }
    }

    private var borderColor: Color {
        switch variant {
        case .subtle:
            return .clear
        case .outlined:
            return AppTheme.Colour.border
        case .hero:
            return isSelected ? .accentColor : AppTheme.Colour.border
        case .glass:
            return AppTheme.Colour.border.opacity(0.28)
        }
    }

    private var borderWidth: CGFloat {
        switch variant {
        case .subtle:
            return 0.5
        case .outlined:
            return 1
        case .hero:
            return isSelected ? 2 : 1
        case .glass:
            return 0.5
        }
    }
}
