import SwiftUI

struct AISuggestionView: View {

    let advice: ComplexityAdvice
    let proPrice: String
    let onUseAI: () -> Void
    let onBasic: () -> Void
    let onDismiss: () -> Void

    private let windowSize: AppTheme.WindowSize = .thin

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 72, height: 72)
                Image(symbol: UpmarketSymbols.ai)
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.top, AppTheme.Spacing.xs)

            VStack(spacing: AppTheme.Spacing.sm) {
                Text(L("ai.suggestion.title"))
                    .font(AppTheme.Font.title3)
                    .fontWeight(.bold)
                Text(L("ai.suggestion.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !advice.reasons.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    ForEach(advice.reasons, id: \.self) { reason in
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                                .font(.caption)
                            Text(reason)
                                .font(.caption)
                        }
                    }
                }
                .padding(AppTheme.Spacing.md)
                .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            }

            VStack(spacing: AppTheme.Spacing.sm) {
                Button(action: onUseAI) {
                    Label(L("ai.suggestion.use_ai", proPrice), systemImage: UpmarketSymbols.ai)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: onBasic) {
                    Text(L("ai.suggestion.basic"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            Button(L("ai.suggestion.cancel"), action: onDismiss)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, AppTheme.Spacing.xs)
        }
        .padding(windowSize.contentPadding)
        .frame(width: windowSize.width)
    }
}
