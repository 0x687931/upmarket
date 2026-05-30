import SwiftUI
import StoreKit

struct PaywallView: View {

    @EnvironmentObject private var store: StoreManager
    @Environment(\.dismiss) private var dismiss

    private let device = DeviceCapability.shared

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
            Text("#")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 32)

            Text("Upmarket")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Convert any document to clean Markdown.\nEverything happens on your Mac — privately.")
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
            // Basic plan
            planRow(
                title: "Upmarket",
                price: store.basicProduct?.displayPrice ?? "$4.99",
                tagline: "For everyday documents",
                features: [
                    "PDF, Word, PowerPoint, HTML → Markdown",
                    "Tables and layout detection",
                    "Scanned document support",
                    "Unlimited conversions",
                    "100% offline, 100% private"
                ],
                badge: nil,
                isHighlighted: false,
                product: store.basicProduct
            )

            // Pro plan
            planRow(
                title: "Upmarket + AI",
                price: store.proProduct?.displayPrice ?? "$9.99",
                tagline: "For complex and research documents",
                features: [
                    "Everything in Upmarket",
                    "Upmarket AI for dense layouts and figures",
                    "Handwritten and low-quality scans",
                    "Research papers and academic content",
                    device.supportsUpmarketAI ? "On-device AI, nothing sent to the cloud" : device.upmarketAIUnavailableReason
                ],
                badge: device.supportsUpmarketAI ? "RECOMMENDED" : "APPLE SILICON",
                isHighlighted: device.supportsUpmarketAI,
                product: device.supportsUpmarketAI ? store.proProduct : nil
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private func planRow(title: String, price: String, tagline: String, features: [String], badge: String?, isHighlighted: Bool, product: Product?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                        if let badge {
                            Text(badge)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isHighlighted ? Color.accentColor : Color.secondary, in: Capsule())
                        }
                    }
                    Text(tagline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(product != nil ? price : "—")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("one-time")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                HStack(spacing: 8) {
                    Image(systemName: (product == nil && index == features.count - 1) ? "xmark.circle" : "checkmark.circle.fill")
                        .foregroundStyle((product == nil && index == features.count - 1) ? Color.secondary : Color.green)
                        .font(.caption)
                    Text(feature)
                        .font(.caption)
                        .foregroundStyle(index == features.count - 1 && product == nil ? Color.secondary : Color.primary)
                }
            }

            if let product {
                Button {
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
                .tint(isHighlighted ? Color.accentColor : Color.secondary)
                .disabled(isPurchasing)
            } else {
                Text("Not available on \(device.chipDescription) Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isHighlighted ? Color.accentColor : Color.secondary.opacity(0.3),
                    lineWidth: isHighlighted ? 2 : 1
                )
        )
        .opacity(product == nil ? 0.6 : 1.0)
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
