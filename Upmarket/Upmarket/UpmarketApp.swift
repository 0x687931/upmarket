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

    @StateObject private var conversionQueue = ConversionQueue.shared
    @StateObject private var historyStore    = ConversionHistoryStore.shared
    @StateObject private var watchedFolders  = WatchedFolderService.shared
    @StateObject private var storeManager    = StoreManager.shared
    @StateObject private var modelManager    = ModelManager.shared
    @StateObject private var featureFlags    = FeatureFlags.shared

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // MARK: Settings window — OS manages title, ⌘, shortcut, and singleton behaviour
        Settings {
            PreferencesView()
                .environmentObject(modelManager)
                .environmentObject(storeManager)
                .environmentObject(historyStore)
                .environmentObject(watchedFolders)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Convert Document…") {
                    openPrimaryConversionWindow(pickFile: true)
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Show Shelf") {
                    AppVisibilityPreference.showShelf = true
                    ShelfWindowController.shared.show(ignoringPreference: true)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }

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

            CommandGroup(replacing: .appTermination) {
                Button("Quit Upmarket") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }

        Window("Report a Problem", id: "reportProblem") {
            ReportProblemView()
                .environmentObject(conversionQueue)
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
    }

    private func openPrimaryConversionWindow(pickFile: Bool = false) {
        MainWindowController.shared.show(pickFile: pickFile)
    }

    init() {
        RuntimePrivilegeGuard.abortIfPrivilegedProcess()
        AppVisibilityPreference.normalizePersistentVisibility()
        AppRuntime.exitIfDuplicateInstance()
        AppRuntime.installTerminationSignalCleanup()
        AppWorkspace.removeStaleWorkspaces()
        AppRuntime.writeUITestWorkspacePathIfRequested()
        if !AppRuntime.isRunningTests {
            FeatureFlags.shared.fetchFlags()
            Task { @MainActor in
                WatchedFolderService.shared.start()
            }
        }

        if AppRuntime.isRunningUITests { return }

        // Show shelf then start tour on first launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard !AppRuntime.isRunningTests else { return }
            guard AppVisibilityPreference.showShelf else {
                if AppVisibilityPreference.showDockIcon {
                    MainWindowController.shared.show()
                }
                return
            }
            ShelfWindowController.shared.centerForFirstLaunchTour()
            ShelfWindowController.shared.show(animate: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                TourManager.shared.startIfNeeded()
            }
        }
    }
}
