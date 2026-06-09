import SwiftUI

struct AppActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: AppTheme.Size.actionIcon, weight: .semibold))
            .foregroundStyle(.primary.opacity(configuration.isPressed ? 0.95 : 0.78))
            .padding(AppTheme.Spacing.xs)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .strokeBorder(Color.primary.opacity(configuration.isPressed ? 0.22 : 0.12), lineWidth: 0.5)
            )
    }
}

struct AppCardStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(isSelected ? AppTheme.Colour.selectedFill : AppTheme.Colour.subtleFill)
            .cornerRadius(AppTheme.Radius.md)
    }
}
