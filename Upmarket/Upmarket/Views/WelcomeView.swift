import SwiftUI
import AppKit

@MainActor
final class WelcomeWindowController: NSWindowController {

    static let shared = WelcomeWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: AppTheme.WindowSize.welcome.width,
                height: AppTheme.WindowSize.welcome.height
            ),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // Window content is a rounded card (see WelcomeView.body) — make the
        // window itself transparent so the card's corners/shadow read correctly
        // against the desktop, and drop AppKit's own rectangular window shadow
        // in favor of the card's shadow.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.center()

        let rootView = WelcomeView { destination, chosenFolderURL in
            SavePreference.shared.configure(destination: destination, chosenFolderURL: chosenFolderURL)
            UserDefaults.standard.set(true, forKey: "upmarket.tourComplete")
            window.close()
            MainWindowController.shared.show()
        }
        window.contentView = NSHostingView(rootView: rootView)

        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct WelcomeView: View {

    var onDismiss: (_ destination: SavePreference.Destination, _ chosenFolderURL: URL?) -> Void

    @State private var saveDestination: SavePreference.Destination = SavePreference.shared.destination
    @State private var chosenFolderURL: URL? = SavePreference.shared.chosenFolderURL

    var body: some View {
        ZStack {
            background
            content
        }
        .frame(width: AppTheme.WindowSize.welcome.width, height: AppTheme.WindowSize.welcome.height)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.WindowSize.welcome.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.WindowSize.welcome.cornerRadius, style: .continuous)
                .strokeBorder(AppTheme.Colour.separator, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.28), radius: 32, x: 0, y: 24) // --shadow-window
    }

    // MARK: - Background

    @ViewBuilder private var background: some View {
        if #available(macOS 26, *) {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
        } else {
            AppTheme.Colour.background
                .ignoresSafeArea()
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            // Icon + headline
            VStack(spacing: 0) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
                    .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 6)

                Text("Convert most things to Markdown.")
                    .font(AppTheme.Font.heroRounded)
                    .tracking(-0.4)
                    .multilineTextAlignment(.center)
                    .padding(.top, AppTheme.Spacing.lg)

                Text("Works on your Mac. No cloud, no account, no waiting.")
                    .font(AppTheme.Font.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 7)
            }

            Spacer()

            // Feature rows
            VStack(alignment: .leading, spacing: 14) {
                featureRow(
                    symbol: "doc.fill",
                    color: AppTheme.Colour.iconGlyphTint,
                    title: "PDFs, Word, PowerPoint and more",
                    detail: "Drop in a file and get clean, readable Markdown out."
                )
                featureRow(
                    symbol: "lock.fill",
                    color: AppTheme.Colour.success,
                    title: "Completely private",
                    detail: "Nothing leaves your Mac. No account, no network."
                )
                featureRow(
                    symbol: "bolt.fill",
                    color: .accentColor,
                    title: "Fast, on-device AI",
                    detail: "Conversion runs locally on Apple Silicon."
                )
            }

            Spacer()

            SaveLocationSettingsView(
                destination: $saveDestination,
                chosenFolderURL: $chosenFolderURL,
                title: "Save files",
                description: "Choose where converted Markdown is saved. You can change this later in Preferences.",
                onChooseFolder: chooseSaveFolder,
                showsCardChrome: true
            )

            // CTA
            VStack(spacing: AppTheme.Spacing.md) {
                getStartedButton

                Text("3 free conversions included. No sign-up needed.")
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(AppTheme.Colour.textTertiary)
            }
        }
        .padding(.top, 42)
        .padding(.horizontal, 44)
        .padding(.bottom, 34)
    }

    // MARK: - Feature row

    private func featureRow(symbol: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: AppTheme.Size.featureIconBox, height: AppTheme.Size.featureIconBox)
                Image(systemName: symbol)
                    .font(.system(size: AppTheme.Size.featureIcon, weight: .medium))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Button

    @ViewBuilder private var getStartedButton: some View {
        if #available(macOS 26, *) {
            Button(action: finishOnboarding) {
                Text("Get Started")
                    .font(AppTheme.Font.body)
                    .frame(width: 220)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .tint(.accentColor)
        } else {
            Button(action: finishOnboarding) {
                Text("Get Started")
                    .font(AppTheme.Font.body)
                    .frame(width: 220)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.accentColor)
        }
    }

    private func chooseSaveFolder() {
        if let url = FileAccessService.shared.chooseSaveDirectory(
            message: "Upmarket will save converted files here."
        ) {
            chosenFolderURL = url
            saveDestination = .chosenFolder
        }
    }

    private func finishOnboarding() {
        onDismiss(saveDestination, chosenFolderURL)
    }
}
