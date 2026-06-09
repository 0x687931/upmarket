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
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon + headline
            VStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)

                VStack(spacing: 6) {
                    Text("Welcome to Upmarket")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Convert documents to clean Markdown.\nPrivate, fast, and 100% on your Mac.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()

            // Feature rows
            VStack(alignment: .leading, spacing: 16) {
                featureRow(
                    symbol: "doc.fill",
                    color: .blue,
                    title: "Any document",
                    detail: "PDF, Word, PowerPoint, images — all converted to readable Markdown."
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
                    title: "Instant results",
                    detail: "Drop a file onto the window or click Choose File to convert in seconds."
                )
            }
            .padding(.horizontal, 48)

            Spacer()

            // CTA
            getStartedButton

            Text("3 free conversions included — no sign-up needed.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)

            Spacer().frame(height: 32)
        }
    }

    // MARK: - Feature row

    private func featureRow(symbol: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 3)
        }
    }

    // MARK: - Button

    @ViewBuilder private var getStartedButton: some View {
        if #available(macOS 26, *) {
            Button(action: onDismiss) {
                Text("Get Started")
                    .fontWeight(.semibold)
                    .frame(width: 200)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        } else {
            Button(action: onDismiss) {
                Text("Get Started")
                    .fontWeight(.semibold)
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}
