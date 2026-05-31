import SwiftUI

struct AISuggestionView: View {

    let advice: ComplexityAdvice
    let onUseAI: () -> Void
    let onBasic: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 72, height: 72)
                Image(symbol: UpmarketSymbols.ai)
                    .font(.system(size: 32))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.top, 8)

            // Message
            VStack(spacing: 8) {
                Text("This document looks complex")
                    .font(.title3)
                    .fontWeight(.bold)

                Text("Upmarket AI is recommended for better results.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Reasons
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

            // Actions
            VStack(spacing: 10) {
                Button(action: onUseAI) {
                    Label("Use Upmarket AI — $9.99", systemImage: "sparkles")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: onBasic) {
                    Text("Convert without AI")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            Button("Cancel", action: onDismiss)
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
        }
        .padding(28)
        .frame(width: 360)
    }
}
