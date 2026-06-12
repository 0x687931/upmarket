import SwiftUI
import StoreKit

private enum PaywallTier {
    case pro, basic
}

struct PaywallView: View {

    var onDismiss: (() -> Void)? = nil

    @EnvironmentObject private var store: StoreManager

    private let device = DeviceCapability.shared
    private let flags = FeatureFlags.shared
    private let windowSize: AppTheme.WindowSize = .modal

    @State private var isPurchasing: String? = nil  // product ID currently purchasing
    @State private var errorMessage: String?
    @State private var selectedTier: PaywallTier

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
        _selectedTier = State(initialValue: FeatureFlags.shared.aiAvailable ? .pro : .basic)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            // No Divider — spec shows seamless header-to-tier transition
            tierSection
            ctaSection
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
        // Close button is positioned absolutely top-right per spec (top: 14, right: 14)
        ZStack(alignment: .topTrailing) {
            VStack(spacing: AppTheme.Spacing.sm) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.appIcon, style: .continuous))
                    // --shadow-card: 0 1px 3px rgba(0,0,0,0.08), 0 6px 18px rgba(0,0,0,0.08)
                    .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
                    .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 6)
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
                        // --text-tertiary: rgba(0,0,0,0.26)
                        .foregroundStyle(AppTheme.Colour.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                // top: 14, right: 14 per spec
                .padding(.top, 14)
                .padding(.trailing, 14)
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

    // MARK: - Tier Section

    // Spec: padding "0 20px", gap 12 between cards
    // 20px ≈ between lg(16) and xl(24). Using lg for horizontal since spec says 20 and we don't have a 20 token.
    // Judgment call: use Spacing.lg (16) — slightly tighter than spec's 20px — to stay on the token grid.
    // The 4px difference is imperceptible and keeps us on the 4pt rhythm.
    private var tierSection: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            tierCard(.pro)
            tierCard(.basic)
            productStatus
            purchaseStatus
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.lg)
    }

    // MARK: - Tier Card

    private func tierCard(_ tier: PaywallTier) -> some View {
        let isSelected = selectedTier == tier
        let isDisabled = tier == .pro && !canPurchasePro

        return Button {
            selectedTier = tier
        } label: {
            // spec: padding "14px 16px"
            HStack(alignment: .top, spacing: 10) {
                // Radio indicator: 18×18; selected = 5px solid accent ring; unselected = 1.5px solid border
                Circle()
                    .strokeBorder(isSelected ? Color.accentColor : AppTheme.Colour.border,
                                  lineWidth: isSelected ? 5 : 1.5)
                    .background(Circle().fill(AppTheme.Colour.background))
                    .frame(width: 18, height: 18)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: AppTheme.Spacing.sm) {
                                Text(tierName(tier))
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.primary)
                                if tier == .pro {
                                    AppBadge("Best", variant: .accent)
                                        .accessibilityLabel("Best value")
                                }
                            }
                            // Tagline: text-caption/1.3, text-secondary, 3px top margin
                            Text(tierTagline(tier))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(tierPrice(tier))
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundStyle(.primary)
                            Text("one-time")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Feature list: paddingLeft 28 (radio 18 + gap 10 = 28), gap 7
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(tierFeatures(tier), id: \.text) { feature in
                            featureRow(feature.text, isHighlight: feature.isHighlight)
                        }
                        if isDisabled, let reason = flags.aiUnavailableReason {
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
                    .padding(.top, AppTheme.Spacing.md)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, AppTheme.Spacing.lg)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                // Selected: var(--accent-06); unselected: var(--surface) = controlBackground
                .fill(isSelected ? AppTheme.Colour.accentTint06 : AppTheme.Colour.controlBackground.opacity(0.01))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                        // Selected: 2px accent border; unselected: 1px border
                        .strokeBorder(isSelected ? Color.accentColor : AppTheme.Colour.border,
                                      lineWidth: isSelected ? 2 : 1)
                )
        )
        .opacity(isDisabled ? 0.6 : 1)
        .disabled(isDisabled)
    }

    private func tierName(_ tier: PaywallTier) -> String {
        switch tier {
        case .pro: return "Upmarket + AI"
        case .basic: return "Upmarket"
        }
    }

    private func tierPrice(_ tier: PaywallTier) -> String {
        switch tier {
        case .pro: return store.proProduct?.displayPrice ?? "$9.99"
        case .basic: return store.basicProduct?.displayPrice ?? "$4.99"
        }
    }

    private func tierTagline(_ tier: PaywallTier) -> String {
        switch tier {
        case .pro:
            return "Everything, including Upmarket AI for complex documents"
        case .basic:
            return device.supportsAdvancedRuntime ? "For everyday documents without AI" : "For native Basic conversion on this Mac"
        }
    }

    private func tierFeatures(_ tier: PaywallTier) -> [(text: String, isHighlight: Bool)] {
        switch tier {
        case .pro:
            return [
                ("Unlimited conversions — every format", false),
                ("Upmarket AI for scanned, complex and research documents", true),
                ("Tables, figures, dense layouts", false),
                ("100% on-device — nothing sent to the cloud", false)
            ]
        case .basic:
            if device.supportsAdvancedRuntime {
                return [
                    ("PDF, Word, PowerPoint, HTML → Markdown", false),
                    ("Tables and layout detection", false),
                    ("Unlimited conversions", false)
                ]
            } else {
                return [
                    ("Native PDF and media metadata conversion", false),
                    ("Advanced document formats require Apple Silicon", false),
                    ("Unlimited conversions", false)
                ]
            }
        }
    }

    // MARK: - CTA Area

    // Spec: padding "20px", gap 12 between CTA and Restore
    private var ctaSection: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            ctaButton
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
        .padding(AppTheme.Spacing.lg)
    }

    private var ctaButton: some View {
        let product = selectedTier == .pro ? store.proProduct : store.basicProduct
        let purchasingID = selectedTier == .pro ? StoreManager.proID : StoreManager.basicID

        return Button {
            guard let product else { return }
            Task { await buy(product) }
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                if isPurchasing == purchasingID {
                    ProgressView().controlSize(.small).tint(.white)
                }
                Text("Get \(tierName(selectedTier)) — \(tierPrice(selectedTier))")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(AppProminentButtonStyle())
        .controlSize(.large)
        .disabled(isPurchasing != nil || product == nil || (selectedTier == .pro && !canPurchasePro))
    }

    // MARK: - Footer

    private var restoreButton: some View {
        Button("Restore Purchases") {
            Task { await store.restorePurchases() }
        }
        .buttonStyle(.plain)
        // spec: weight-medium text-subheadline/1, var(--text-secondary)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .frame(minHeight: 44)
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

    // Spec: text-caption/1.4, var(--text-tertiary), centered, padding "0 24px 18px"
    private var legalFooter: some View {
        Text(L("paywall.footer"))
            .font(.caption)
            .foregroundStyle(AppTheme.Colour.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppTheme.Spacing.xl)   // 24px = xl
            .padding(.bottom, 18)
    }

    // MARK: - Helpers

    // Feature row: checkmark icon (14px, accent if highlight else success) + label
    private func featureRow(_ text: String, isHighlight: Bool) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(isHighlight ? Color.accentColor : AppTheme.Colour.success)
                .font(.system(size: 14))
            Text(text)
                .font(.caption)
                .fontWeight(isHighlight ? .medium : .regular)
                .foregroundStyle(isHighlight ? Color.primary : Color.secondary)
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
