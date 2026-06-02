import Darwin
import SwiftUI

private enum RuntimePrivilegeGuard {
    static func abortIfPrivilegedProcess() {
        let realUserID = getuid()
        let effectiveUserID = geteuid()
        let realGroupID = getgid()
        let effectiveGroupID = getegid()

        guard realUserID != 0,
              effectiveUserID != 0,
              realUserID == effectiveUserID,
              realGroupID == effectiveGroupID else {
            fputs("Upmarket refuses to run with elevated privileges.\n", stderr)
            _exit(77)
        }
    }
}

@main
struct UpmarketApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var pythonBridge    = PythonBridge.shared
    @StateObject private var conversionQueue = ConversionQueue.shared
    @StateObject private var storeManager    = StoreManager.shared
    @StateObject private var modelManager    = ModelManager.shared
    @StateObject private var featureFlags    = FeatureFlags.shared

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {

        // MARK: Main window — hidden immediately, never shown on launch
        // WindowGroup is kept so Preferences/output views can open windows on demand.
        // The window is ordered out before it can be seen.
        WindowGroup {
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear {
                    // Order out instantly — no flash
                    NSApp.windows
                        .filter { !($0 is NSPanel) && $0.className != "NSStatusBarWindow" }
                        .forEach { $0.orderOut(nil) }
                }
        }
        .defaultSize(width: 0, height: 0)
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
                Button("Report a Problem…") {
                    openWindow(id: "reportProblem")
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

        Window("Report a Problem", id: "reportProblem") {
            ReportProblemView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 620, height: 560)

        // MARK: Onboarding window — shown on first launch
        Window("Welcome to Upmarket", id: "onboarding") {
            OnboardingView()
                .environmentObject(storeManager)
                .environmentObject(modelManager)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 480, height: 400)

        // MARK: Menu bar icon
        MenuBarExtra {
            MenuBarDropdown()
                .environmentObject(storeManager)
                .environmentObject(conversionQueue)
        } label: {
            MenuBarIconView(isConverting: conversionQueue.isConverting)
        }
        .menuBarExtraStyle(.window)
    }

    init() {
        RuntimePrivilegeGuard.abortIfPrivilegedProcess()
        AppWorkspace.removeStaleWorkspaces()
        Task { @MainActor in
            PythonBridge.shared.setup()
        }
        FeatureFlags.shared.fetchFlags()

        // Show shelf then start tour on first launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard !AppRuntime.isRunningTests else { return }
            ShelfWindowController.shared.show(animate: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                TourManager.shared.startIfNeeded()
            }
        }
    }
}
