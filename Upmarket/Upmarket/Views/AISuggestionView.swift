import SwiftUI

struct AISuggestionView: View {

    let advice: ComplexityAdvice
    let proPrice: String
    let onUseAI: () -> Void
    let onBasic: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 72, height: 72)
                Image(symbol: UpmarketSymbols.ai)
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.top, 8)

            VStack(spacing: 8) {
                Text(L("ai.suggestion.title"))
                    .font(.title3)
                    .fontWeight(.bold)
                Text(L("ai.suggestion.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !advice.reasons.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(advice.reasons, id: \.self) { reason in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                                .font(.caption)
                            Text(reason)
                                .font(.caption)
                        }
                    }
                }
                .padding(14)
                .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }

            VStack(spacing: 10) {
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
                .padding(.bottom, 4)
        }
        .padding(28)
        .frame(width: 360)
    }
}
