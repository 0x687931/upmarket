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
    @State private var selectedTier: PaywallTier

    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
        _selectedTier = State(initialValue: FeatureFlags.shared.aiAvailable ? .pro : .basic)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                VStack(spacing: 12) {
                    if flags.aiAvailable {
                        tierCard(.pro)
                    }
                    tierCard(.basic)
                }
                .padding(.horizontal, 20)

                VStack(spacing: 12) {
                    ctaButton
                    restoreButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                legalFooter
            }
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(AppTheme.Colour.controlBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .strokeBorder(AppTheme.Colour.separator, lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        }
        .frame(width: windowSize.width)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            await store.loadProducts()
        }
        .onAppear(perform: normalizeSelectedTier)
        .onChange(of: flags.aiAvailable) { _ in
            normalizeSelectedTier()
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 12) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
                    .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
                    .padding(.top, 32)

                Text(headerTitle)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 20)

            if onDismiss != nil {
                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(AppPlainButtonStyle())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close")
                .padding(14)
            }
        }
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

    // MARK: - Tier Card

    private func tierCard(_ tier: PaywallTier) -> some View {
        let isSelected = selectedTier == tier
        let isDisabled = tier == .pro && !canPurchasePro

        return Button {
            guard !isDisabled else { return }
            selectedTier = tier
        } label: {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                Circle()
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: isSelected ? 5 : 1.5)
                    .frame(width: 18, height: 18)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                                    HStack(spacing: AppTheme.Spacing.sm) {
                                        Text(tierName(tier))
                                            .font(.title3)
                                            .fontWeight(.bold)
                                        if tier == .pro {
                                            AppBadge("Best", variant: .accent)
                                        }
                                    }
                            Text(tierTagline(tier))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: AppTheme.Spacing.xs) {
                            Text(tierPrice(tier))
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("one-time")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        ForEach(tierFeatures(tier), id: \.text) { feature in
                            featureRow(feature.text, isHighlight: feature.isHighlight)
                        }
                    }
                }
            }
        }
        .buttonStyle(AppCardStyle(
            variant: tier == .pro ? .hero : .outlined,
            isSelected: isSelected,
            isDisabled: isDisabled
        ))
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
                ("Upmarket AI for scanned, complex and research documents", true),
                ("Unlimited conversions — every format", false),
                ("100% on-device — nothing sent to the cloud", false)
            ]
        case .basic:
            if device.supportsAdvancedRuntime {
                return [
                    ("PDF, Word, PowerPoint, HTML → Markdown", false),
                    ("Unlimited conversions", false)
                ]
            } else {
                return [
                    ("Native PDF and media metadata conversion", false),
                    ("Unlimited conversions", false)
                ]
            }
        }
    }

    // MARK: - CTA

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
        .buttonStyle(AppPlainButtonStyle())
        .foregroundStyle(.secondary)
        .frame(minHeight: 44)
        .accessibilityLabel("Restore previous purchases")
        .accessibilityHint("Restores any previous Upmarket purchases from the App Store")
    }

    private var legalFooter: some View {
        Text(L("paywall.footer"))
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
    }

    // MARK: - Helpers

    private func featureRow(_ text: String, isHighlight: Bool) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(isHighlight ? Color.accentColor : AppTheme.Colour.success)
                .font(.caption)
            Text(text)
                .font(.caption)
                .fontWeight(isHighlight ? .medium : .regular)
        }
    }

    private var canPurchasePro: Bool {
        flags.aiAvailable
    }

    private func normalizeSelectedTier() {
        if selectedTier == .pro && !canPurchasePro {
            selectedTier = .basic
        }
    }

    private func buy(_ product: Product) async {
        isPurchasing = product.id
        do {
            try await store.purchase(product)
            onDismiss?()
        } catch {
            // Keep the flow silent here; the sheet already exposes restore/purchase actions.
        }
        isPurchasing = nil
    }
}

#Preview {
    PaywallView(onDismiss: nil)
        .environmentObject(StoreManager.shared)
}
