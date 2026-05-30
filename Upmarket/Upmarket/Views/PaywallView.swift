import SwiftUI
import StoreKit

struct PaywallView: View {

    @EnvironmentObject private var store: StoreManager
    @Environment(\.dismiss) private var dismiss

    @State private var isPurchasing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            plans
            footer
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.accent)
                .padding(.top, 32)

            Text("Upmarket")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Convert any document to Markdown\nusing on-device AI. Your files never leave your Mac.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
        }
    }

    // MARK: - Plans

    private var plans: some View {
        VStack(spacing: 12) {
            planRow(
                title: "Basic",
                price: store.basicProduct?.displayPrice ?? "$4.99",
                description: "PDF, Word, PowerPoint, HTML → Markdown",
                features: ["Layout & table detection", "OCR for scanned documents", "Unlimited conversions", "100% offline"],
                isHighlighted: false,
                product: store.basicProduct,
                isPro: false
            )

            planRow(
                title: "Pro",
                price: store.proProduct?.displayPrice ?? "$9.99",
                description: "Everything in Basic, plus AI for complex documents",
                features: ["SmolDocling VLM on-device AI", "Scanned & handwritten PDFs", "Dense layouts & figures", "Research papers & tables"],
                isHighlighted: true,
                product: store.proProduct,
                isPro: true
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func planRow(title: String, price: String, description: String, features: [String], isHighlighted: Bool, product: Product?, isPro: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                        if isPro {
                            Text("RECOMMENDED")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor, in: Capsule())
                        }
                    }
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(price)
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("one-time")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(features, id: \.self) { feature in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text(feature)
                        .font(.caption)
                }
            }

            Button {
                guard let product else { return }
                Task { await buyProduct(product) }
            } label: {
                HStack {
                    if isPurchasing {
                        ProgressView().controlSize(.small)
                    }
                    Text("Buy \(title) — \(price)")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(isHighlighted ? .accentColor : .secondary)
            .disabled(isPurchasing || product == nil)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isHighlighted ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isHighlighted ? 2 : 1)
        )
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 8) {
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Restore Purchases") {
                Task { await store.restorePurchases() }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)

            Text("Payment processed by Apple. One-time purchase, no subscription.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

    private func buyProduct(_ product: Product) async {
        isPurchasing = true
        errorMessage = nil
        do {
            try await store.purchase(product)
            dismiss()
        } catch {
            errorMessage = "Purchase failed. Please try again."
        }
        isPurchasing = false
    }
}

#Preview {
    PaywallView()
        .environmentObject(StoreManager.shared)
}
