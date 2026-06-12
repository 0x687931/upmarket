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

    var body: some Scene {
        // All windows are NSWindowController singletons — no SwiftUI scene restoration surprises.
        // Commands and keyboard shortcuts are wired here; windows open via their controllers.
        Settings {
            // Placeholder keeps SwiftUI's Settings menu item wired up;
            // the real window is PreferencesWindowController.
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Convert Document…") {
                    MainWindowController.shared.show(pickFile: true)
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    PreferencesWindowController.shared.show()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(after: .help) {
                Button("Report a Problem…") {
                    ReportProblemWindowController.shared.show()
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

            // Remove the system-generated "Close" (xmark) item — not meaningful
            // in a shelf/menu bar app that has no persistent document windows.
            CommandGroup(replacing: .windowList) {}
        }
    }

    private func openPrimaryConversionWindow(pickFile: Bool = false) {
        MainWindowController.shared.show(pickFile: pickFile)
    }

    init() {
        AppLaunchMetrics.reset()
        RuntimePrivilegeGuard.abortIfPrivilegedProcess()
        AppLaunchMetrics.mark("privilege-check")
        AppVisibilityPreference.normalizePersistentVisibility()
        AppLaunchMetrics.mark("visibility-normalized")
        AppRuntime.exitIfDuplicateInstance()
        AppLaunchMetrics.mark("single-instance-checked")
        AppRuntime.installTerminationSignalCleanup()
        AppRuntime.writeUITestWorkspacePathIfRequested()
        AppRuntime.scheduleStartupCleanup()
        AppLaunchMetrics.mark("startup-cleanup-scheduled")
        if !AppRuntime.isRunningTests {
            FeatureFlags.shared.fetchFlags()
            Task { @MainActor in
                WatchedFolderService.shared.start()
            }
        }
        AppLaunchMetrics.mark("services-kicked-off")

        if AppRuntime.isRunningUITests { return }

        DispatchQueue.main.async {
            guard !AppRuntime.isRunningTests else { return }
            if !UserDefaults.standard.bool(forKey: "upmarket.tourComplete") {
                WelcomeWindowController.shared.show()
                AppLaunchMetrics.mark("first-surface-welcome")
            } else if AppVisibilityPreference.showShelf {
                ShelfWindowController.shared.show(animate: true)
                AppLaunchMetrics.mark("first-surface-shelf")
            } else {
                MainWindowController.shared.show()
                AppLaunchMetrics.mark("first-surface-main")
            }
        }
    }
}
