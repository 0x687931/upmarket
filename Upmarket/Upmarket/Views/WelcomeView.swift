import SwiftUI
import AppKit

@MainActor
final class WelcomeWindowController: NSWindowController {

    static let shared = WelcomeWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()

        let rootView = WelcomeView {
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

    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            background
            content
        }
        .frame(width: 520, height: 460)
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
            Spacer()

            // Icon + headline
            VStack(spacing: AppTheme.Spacing.lg) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: AppTheme.Size.appIconSize, height: AppTheme.Size.appIconSize)

                VStack(spacing: AppTheme.Spacing.xs) {
                    Text("Convert most things to Markdown.")
                        .font(AppTheme.Font.largeTitle)

                    Text("Works on your Mac. No cloud, no account, no waiting.")
                        .font(AppTheme.Font.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()

            // Feature rows
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                featureRow(
                    symbol: "doc.fill",
                    color: .blue,
                    title: "PDFs, Word, PowerPoint and more",
                    detail: "Drop in a file and get clean, readable Markdown out."
                )
                featureRow(
                    symbol: "lock.fill",
                    color: .green,
                    title: "Completely private",
                    detail: "Nothing leaves your Mac. No account, no cloud, no network required."
                )
                featureRow(
                    symbol: "bolt.fill",
                    color: .orange,
                    title: "Fast, on-device AI",
                    detail: "Conversion runs locally using Apple Silicon. No waiting on a server."
                )
            }
            .padding(.horizontal, AppTheme.Spacing.xxxl)

            Spacer()

            // CTA
            getStartedButton

            Text("3 free conversions included. No sign-up needed.")
                .font(AppTheme.Font.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, AppTheme.Spacing.md)

            Spacer().frame(height: AppTheme.Spacing.xxl)
        }
    }

    // MARK: - Feature row

    private func featureRow(symbol: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .fill(color.opacity(0.12))
                    .frame(width: AppTheme.Size.featureIconBox, height: AppTheme.Size.featureIconBox)
                Image(systemName: symbol)
                    .font(.system(size: AppTheme.Size.featureIcon, weight: .medium))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(title)
                    .font(AppTheme.Font.body)
                Text(detail)
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, AppTheme.Spacing.xs)
        }
    }

    // MARK: - Button

    @ViewBuilder private var getStartedButton: some View {
        if #available(macOS 26, *) {
            Button(action: onDismiss) {
                Text("Get Started")
                    .font(AppTheme.Font.body)
                    .frame(width: 200)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        } else {
            Button(action: onDismiss) {
                Text("Get Started")
                    .font(AppTheme.Font.body)
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}
