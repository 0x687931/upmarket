import SwiftUI

struct AppTextEditorStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    .fill(AppTheme.Colour.controlBackground.opacity(0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    .strokeBorder(AppTheme.Colour.border, lineWidth: 1)
            )
    }
}

extension View {
    func appTextEditorChrome() -> some View {
        modifier(AppTextEditorStyle())
    }
}
