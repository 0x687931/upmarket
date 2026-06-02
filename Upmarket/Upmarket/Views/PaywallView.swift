import SwiftUI
import StoreKit

struct PaywallView: View {

    var onPurchaseComplete: (() -> Void)? = nil

    @EnvironmentObject private var store: StoreManager
    @Environment(\.dismiss) private var dismiss

    private let device = DeviceCapability.shared
    private let flags = FeatureFlags.shared

    @State private var isPurchasing: String? = nil  // product ID currently purchasing
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 12) {
                    if canPurchasePro {
                        proCard
                    } else {
                        proUnavailableCard
                    }
                    basicCard
                    packCard
                    productStatus
                    purchaseStatus
                    restoreButton
                }
                .padding(24)
            }
            legalFooter
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            await store.loadProducts()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            Text("#")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 28)

            Text("Unlock Upmarket")
                .font(.title2)
                .fontWeight(.bold)

            Text("Convert unlimited documents, privately, on your Mac.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 20)
        }
    }

    // MARK: - Pro Card (hero)

    private var proCard: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Top: price + badge
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Upmarket + AI")
                            .font(.title3)
                            .fontWeight(.bold)
                        Text("BEST")
                            .font(.caption2)
                            .fontWeight(.heavy)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.accentColor, in: Capsule())
                    }
                    Text("Everything, including Upmarket AI for complex documents")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(store.proProduct?.displayPrice ?? "$9.99")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("one-time")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Features
            VStack(alignment: .leading, spacing: 7) {
                featureRow("Unlimited conversions — every format", isHighlight: false)
                featureRow("Upmarket AI for scanned, complex and research documents", isHighlight: true)
                featureRow("Tables, figures, dense layouts", isHighlight: false)
                featureRow("100% on-device — nothing sent to the cloud", isHighlight: false)
                if let reason = flags.aiUnavailableReason {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // CTA
            Button {
                guard let product = store.proProduct else { return }
                Task { await buy(product) }
            } label: {
                HStack(spacing: 8) {
                    if isPurchasing == StoreManager.proID {
                        ProgressView().controlSize(.small).tint(.white)
                    }
                    Text("Get Upmarket + AI — \(store.proProduct?.displayPrice ?? "$9.99")")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isPurchasing != nil || store.proProduct == nil || !canPurchasePro)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.accentColor.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                )
        )
    }

    private var proUnavailableCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.secondary)
                Text("Upmarket + AI")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text("Unavailable")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            Text(flags.aiUnavailableReason ?? device.upmarketAIUnavailableReason)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Use Upmarket for unlimited private conversion on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Basic Card (secondary)

    private var basicCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: "Upmarket")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text("For everyday documents without AI")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(store.basicProduct?.displayPrice ?? "$4.99")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("one-time")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                featureRow("PDF, Word, PowerPoint, HTML → Markdown", isHighlight: false)
                featureRow("Tables and layout detection", isHighlight: false)
                featureRow("Unlimited conversions", isHighlight: false)
            }

            Button {
                guard let product = store.basicProduct else { return }
                Task { await buy(product) }
            } label: {
                HStack(spacing: 8) {
                    if isPurchasing == StoreManager.basicID {
                        ProgressView().controlSize(.small)
                    }
                    Text("Get Upmarket — \(store.basicProduct?.displayPrice ?? "$4.99")")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(isPurchasing != nil || store.basicProduct == nil)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Pack Card (last resort)

    private var packCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Just need a few conversions?")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("5 documents for \(store.packProduct?.displayPrice ?? "$0.99")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                guard let product = store.packProduct else { return }
                Task { await buy(product) }
            } label: {
                HStack(spacing: 6) {
                    if isPurchasing == StoreManager.packID {
                        ProgressView().controlSize(.small)
                    }
                    Text(store.packProduct?.displayPrice ?? "$0.99")
                        .fontWeight(.medium)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isPurchasing != nil || store.packProduct == nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Footer

    private var restoreButton: some View {
        Button("Restore Purchases") {
            Task { await store.restorePurchases() }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    @ViewBuilder private var productStatus: some View {
        if let error = store.productLoadError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        } else if !store.productsLoaded {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading purchase options...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    @ViewBuilder private var purchaseStatus: some View {
        if let errorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Dismiss") {
                    self.errorMessage = nil
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var legalFooter: some View {
        Text(L("paywall.footer"))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private func featureRow(_ text: String, isHighlight: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(isHighlight ? Color.accentColor : Color.green)
                .font(.caption)
            Text(text)
                .font(.caption)
                .fontWeight(isHighlight ? .medium : .regular)
        }
    }

    private var canPurchasePro: Bool {
        flags.aiAvailable
    }

    private func buy(_ product: Product) async {
        if product.id == StoreManager.proID && !canPurchasePro {
            errorMessage = flags.aiUnavailableReason ?? device.upmarketAIUnavailableReason
            return
        }
        isPurchasing = product.id
        errorMessage = nil
        do {
            try await store.purchase(product)
            onPurchaseComplete?()
            dismiss()
        } catch {
            errorMessage = "Purchase could not be completed. Please try again or use Restore Purchases."
        }
        isPurchasing = nil
    }
}

#Preview {
    PaywallView()
        .environmentObject(StoreManager.shared)
}
