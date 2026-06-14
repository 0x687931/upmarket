import SwiftUI
import StoreKit

private enum PaywallTier {
    case basic, pro, max
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
        _selectedTier = State(initialValue: .pro)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                VStack(spacing: 12) {
                    if !store.isPurchased {
                        tierCard(.basic)
                    }
                    if store.tier < .pro {
                        tierCard(.pro)
                    }
                    if flags.aiAvailable {
                        tierCard(.max)
                    }
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
        .onChange(of: flags.aiAvailable) { _ in normalizeSelectedTier() }
    }

    // MARK: - Header

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 12) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.appIcon, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
                    .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 6)
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
                .accessibilityIdentifier("PaywallCloseButton")
                .padding(14)
            }
        }
    }

    private var headerTitle: String {
        store.tier >= .pro ? "Upgrade to Upmarket Max" : "Upgrade to Upmarket Pro"
    }

    private var headerSubtitle: String {
        store.tier >= .pro
            ? "Add AI for complex, scanned, and research documents."
            : "Unlock enhanced conversion and AI capabilities."
    }

    // MARK: - Tier Card

    private func tierCard(_ tier: PaywallTier) -> some View {
        let isSelected = selectedTier == tier
        let isDisabled = tier == .max && !canPurchaseMax

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
                                        if tier == .max {
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
                                .font(.title3)
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
            variant: tier == .max ? .hero : .outlined,
            isSelected: isSelected,
            isDisabled: isDisabled
        ))
        .disabled(isDisabled)
        .accessibilityIdentifier(tier == .max ? "PaywallMaxTierCard" : (tier == .pro ? "PaywallProTierCard" : "PaywallBasicTierCard"))
        .accessibilityValue(isSelected ? "selected" : "deselected")
    }

    private func tierName(_ tier: PaywallTier) -> String {
        switch tier {
        case .basic: return "Upmarket Basic"
        case .pro:   return "Upmarket Pro"
        case .max:   return "Upmarket Max"
        }
    }

    private func tierPrice(_ tier: PaywallTier) -> String {
        switch tier {
        case .basic: return store.basicProduct?.displayPrice ?? AppTier.basic.price
        case .pro:   return store.proProduct?.displayPrice ?? AppTier.pro.price
        case .max:   return store.maxProduct?.displayPrice ?? AppTier.max.price
        }
    }

    private func tierTagline(_ tier: PaywallTier) -> String {
        switch tier {
        case .basic: return "Everyday documents — Word, PDF, HTML, images, and OCR"
        case .pro:   return "Spreadsheets, audio, complex PDFs, batch, and the command-line tool"
        case .max:   return "AI pipeline for scanned, handwritten, and research documents"
        }
    }

    private func tierFeatures(_ tier: PaywallTier) -> [(text: String, isHighlight: Bool)] {
        switch tier {
        case .basic:
            return [
                ("Word, PDF, HTML, CSV, text → Markdown", true),
                ("Scanned PDF & image OCR, batch conversion", false),
                ("100% on-device — nothing sent to the cloud", false)
            ]
        case .pro:
            return [
                ("Spreadsheets, presentations, ebooks, audio", true),
                ("Complex PDF layout + table extraction, command-line tool", false),
                ("Everything in Basic", false)
            ]
        case .max:
            return [
                ("Upmarket AI for scanned, complex and research documents", true),
                ("Handwriting & advanced table repair — everything in Pro", false),
                ("100% on-device — nothing sent to the cloud", false)
            ]
        }
    }

    // MARK: - CTA

    private var selectedProduct: Product? {
        switch selectedTier {
        case .basic: return store.basicProduct
        case .pro:   return store.proProduct
        case .max:   return store.maxProduct
        }
    }

    private var selectedProductID: String {
        switch selectedTier {
        case .basic: return StoreManager.basicID
        case .pro:   return StoreManager.proID
        case .max:   return StoreManager.maxID
        }
    }

    private var ctaButton: some View {
        let product = selectedProduct
        let purchasingID = selectedProductID

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
        .disabled(isPurchasing != nil || product == nil || (selectedTier == .max && !canPurchaseMax))
        .accessibilityIdentifier("PaywallCTAButton")
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
        .accessibilityIdentifier("PaywallRestoreButton")
    }

    private var legalFooter: some View {
        Text(L("paywall.footer"))
            .font(.caption)
            .foregroundStyle(AppTheme.Colour.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
    }

    // MARK: - Helpers

    private func featureRow(_ text: String, isHighlight: Bool) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(isHighlight ? Color.accentColor : AppTheme.Colour.success)
                .font(.system(size: 14))
            Text(text)
                .font(.caption)
                .fontWeight(isHighlight ? .medium : .regular)
        }
    }

    private var canPurchaseMax: Bool { flags.aiAvailable }

    private func normalizeSelectedTier() {
        if store.tier >= .pro {
            // Only Max card shown — force selection to it
            selectedTier = .max
        } else if selectedTier == .max && !canPurchaseMax {
            selectedTier = .pro
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
