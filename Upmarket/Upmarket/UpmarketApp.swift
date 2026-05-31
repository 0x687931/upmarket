import SwiftUI

@main
struct UpmarketApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var pythonBridge    = PythonBridge.shared
    @StateObject private var conversionService = ConversionService.shared
    @StateObject private var storeManager    = StoreManager.shared
    @StateObject private var modelManager    = ModelManager.shared
    @StateObject private var featureFlags    = FeatureFlags.shared

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {

        // MARK: Main window — only opens on demand (not on launch)
        WindowGroup {
            ContentView()
                .environmentObject(pythonBridge)
                .environmentObject(conversionService)
                .environmentObject(storeManager)
                .environmentObject(modelManager)
                .onAppear {
                    // Close the main window on launch — shelf is the primary UI
                    DispatchQueue.main.async {
                        NSApp.windows.first { $0.isKeyWindow }?.close()
                    }
                }
        }
        .commands {
            // File menu
            CommandGroup(replacing: .newItem) {
                Button("Convert Document…") {
                    NotificationCenter.default.post(name: .openFilePicker, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Show Shelf") {
                    ShelfWindowController.shared.toggle()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            // Settings
            CommandGroup(replacing: .appSettings) {
                Button("Preferences…") {
                    openWindow(id: "preferences")
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            // Help menu additions
            CommandGroup(after: .help) {
                Button("Report an Issue…") {
                    if let url = URL(string: "mailto:support@upmarket.app?subject=Upmarket%20Issue") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Divider()
                Button("Join Discord Community…") {
                    if let url = URL(string: "https://discord.gg/upmarket") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            // Ensure Quit Upmarket appears with Cmd+Q
            CommandGroup(replacing: .appTermination) {
                Button("Quit Upmarket") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }

        // MARK: Preferences window
        Window("Preferences", id: "preferences") {
            PreferencesView()
                .environmentObject(modelManager)
                .environmentObject(storeManager)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 560, height: 440)

        // MARK: Onboarding window — shown on first launch
        Window("Welcome to Upmarket", id: "onboarding") {
            OnboardingView()
                .environmentObject(storeManager)
                .environmentObject(modelManager)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 480, height: 400)

        // MARK: Menu bar icon — minimal, opens shelf or main window
        MenuBarExtra {
            MenuBarView()
                .environmentObject(conversionService)
                .environmentObject(storeManager)
                .environmentObject(modelManager)
        } label: {
            // SF Symbol: "number" — template image for menu bar
            // symbolEffect(.pulse) shows activity on macOS 14+ (Variable Draw)
            if #available(macOS 14.0, *) {
                Image(systemName: conversionService.isConverting ? "number.circle.fill" : "number")
                    .symbolEffect(.pulse, isActive: conversionService.isConverting)
            } else {
                Image(systemName: conversionService.isConverting ? "number.circle.fill" : "number")
            }
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        Task { @MainActor in
            PythonBridge.shared.setup()
        }
        FeatureFlags.shared.fetchFlags()

        // Always show the shelf — it's the primary UI
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            ShelfWindowController.shared.show(animate: true)
        }
    }
}
