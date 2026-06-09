import SwiftUI
import StoreKit

struct PaywallView: View {

    var onDismiss: (() -> Void)? = nil

    @EnvironmentObject private var store: StoreManager

    private let device = DeviceCapability.shared
    private let flags = FeatureFlags.shared
    private let windowSize: AppTheme.WindowSize = .thin

    @State private var isPurchasing: String? = nil  // product ID currently purchasing
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: AppTheme.Spacing.md) {
                    if canPurchasePro {
                        proCard
                    } else {
                        proUnavailableCard
                    }
                    basicCard
                    productStatus
                    purchaseStatus
                    restoreButton
                    if onDismiss != nil {
                        Button("Not Now") { onDismiss?() }
                            .buttonStyle(.plain)
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .frame(minHeight: 44)
                            .accessibilityLabel("Dismiss paywall")
                    }
                }
                .padding(windowSize.contentPadding)
            }
            legalFooter
        }
        .frame(width: windowSize.width)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            await store.loadProducts()
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "number")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, AppTheme.Spacing.xxl)

                Text(headerTitle)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppTheme.Spacing.xxl)

                if let badge = trialContextBadge {
                    Text(badge)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.vertical, AppTheme.Spacing.xs)
                        .background(.quaternary, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, AppTheme.Spacing.lg)

            if onDismiss != nil {
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .padding(AppTheme.Spacing.md)
            }
        }
    }

    private var trialContextBadge: String? {
        if store.hasProOrAbove { return nil }
        if store.hasBasicOrAbove { return "Upgrade to add Upmarket AI" }
        if store.freeDocsRemaining > 0 {
            let n = store.freeDocsRemaining
            return "\(n) free conversion\(n == 1 ? "" : "s") remaining"
        }
        if store.packCredits > 0 {
            return "\(store.packCredits) doc pack credit\(store.packCredits == 1 ? "" : "s") remaining"
        }
        return "Free trial ended — unlock to keep converting"
    }

    private var headerTitle: String {
        store.hasBasicOrAbove ? "Add Upmarket AI" : "Unlock Upmarket"
    }

    private var headerSubtitle: String {
        if store.hasBasicOrAbove {
            return "Add Upmarket AI for complex and scanned documents."
        }
        return "Convert unlimited documents, privately, on your Mac."
    }

    // MARK: - Pro Card (hero)

    private var proCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {

            // Top: price + badge
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Text("Upmarket + AI")
                            .font(.title3)
                            .fontWeight(.bold)
                        Text("BEST")
                            .font(.caption2)
                            .fontWeight(.heavy)
                            .foregroundStyle(.white)
                            .padding(.horizontal, AppTheme.Spacing.sm)
                            .padding(.vertical, AppTheme.Spacing.xs)
                            .background(Color.accentColor, in: Capsule())
                            .accessibilityLabel("Best value")
                    }
                    Text("Everything, including Upmarket AI for complex documents")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: AppTheme.Spacing.xs) {
                    Text(store.proProduct?.displayPrice ?? "$9.99")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("one-time")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Features
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                featureRow("Unlimited conversions — every format", isHighlight: false)
                featureRow("Upmarket AI for scanned, complex and research documents", isHighlight: true)
                featureRow("Tables, figures, dense layouts", isHighlight: false)
                featureRow("100% on-device — nothing sent to the cloud", isHighlight: false)
                if let reason = flags.aiUnavailableReason {
                    HStack(spacing: AppTheme.Spacing.sm) {
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
                HStack(spacing: AppTheme.Spacing.sm) {
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
        .padding(AppTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .fill(Color.accentColor.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                )
        )
    }

    private var proUnavailableCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.sm) {
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
        .padding(AppTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Basic Card (secondary)

    private var basicCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text(verbatim: "Upmarket")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Text(device.supportsAdvancedRuntime ? "For everyday documents without AI" : "For native Basic conversion on this Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: AppTheme.Spacing.xs) {
                    Text(store.basicProduct?.displayPrice ?? "$4.99")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("one-time")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                if device.supportsAdvancedRuntime {
                    featureRow("PDF, Word, PowerPoint, HTML → Markdown", isHighlight: false)
                    featureRow("Tables and layout detection", isHighlight: false)
                } else {
                    featureRow("Native PDF and media metadata conversion", isHighlight: false)
                    featureRow("Advanced document formats require Apple Silicon", isHighlight: false)
                }
                featureRow("Unlimited conversions", isHighlight: false)
            }

            Button {
                guard let product = store.basicProduct else { return }
                Task { await buy(product) }
            } label: {
                HStack(spacing: AppTheme.Spacing.sm) {
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
        .padding(AppTheme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Footer

    private var restoreButton: some View {
        Button("Restore Purchases") {
            Task { await store.restorePurchases() }
        }
        .buttonStyle(.plain)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(minHeight: 44)
        .padding(.top, AppTheme.Spacing.xs)
        .accessibilityLabel("Restore previous purchases")
        .accessibilityHint("Restores any previous Upmarket purchases from the App Store")
    }

    @ViewBuilder private var productStatus: some View {
        if let error = store.productLoadError {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppTheme.Spacing.md)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
        } else if !store.productsLoaded {
            HStack(spacing: AppTheme.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text("Loading purchase options...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, AppTheme.Spacing.xs)
        }
    }

    @ViewBuilder private var purchaseStatus: some View {
        if let errorMessage {
            HStack(spacing: AppTheme.Spacing.sm) {
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
            .padding(AppTheme.Spacing.md)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
        }
    }

    private var legalFooter: some View {
        Text(L("paywall.footer"))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppTheme.Spacing.xl)
            .padding(.vertical, AppTheme.Spacing.md)
    }

    // MARK: - Helpers

    private func featureRow(_ text: String, isHighlight: Bool) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
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
            onDismiss?()
        } catch {
            errorMessage = "Purchase could not be completed. Please try again or use Restore Purchases."
        }
        isPurchasing = nil
    }
}

#Preview {
    PaywallView(onDismiss: nil)
        .environmentObject(StoreManager.shared)
}
