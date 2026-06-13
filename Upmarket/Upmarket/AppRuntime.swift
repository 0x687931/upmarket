import AppKit
import Darwin
import Foundation

enum AppRuntime {
    enum SingleInstanceLockAcquisition: Equatable {
        case acquired(URL)
        case alreadyRunning(URL, pid_t?)
        case unavailable
    }

    private static let appGroupID = "group.com.upmarket.app"
    private static var terminationSignalSources: [DispatchSourceSignal] = []
    private static var singleInstanceLockFD: CInt = -1
    private static var acquiredSingleInstanceLockURL: URL?

    static var isRunningUITests: Bool {
        ProcessInfo.processInfo.environment["UPMARKET_UI_TESTING"] == "1"
    }

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || isRunningUITests
    }

    static var isOpeningPaywall: Bool {
        ProcessInfo.processInfo.environment["UPMARKET_UI_TEST_OPEN_PAYWALL"] == "1"
    }

    static var isOpeningPreferences: Bool {
        ProcessInfo.processInfo.environment["UPMARKET_UI_TEST_OPEN_PREFERENCES"] == "1"
    }

    static var isOpeningShelf: Bool {
        ProcessInfo.processInfo.environment["UPMARKET_UI_TEST_OPEN_SHELF"] == "1"
    }

    static func installTerminationSignalCleanup() {
        guard terminationSignalSources.isEmpty else { return }

        for signalNumber in [SIGTERM, SIGINT] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                releaseSingleInstanceLock()
                AppWorkspace.removeStaleWorkspaces()
                exit(0)
            }
            source.resume()
            terminationSignalSources.append(source)
        }
    }

    static func scheduleStartupCleanup() {
        if isRunningTests {
            AppWorkspace.removeStaleWorkspaces()
            return
        }
        DispatchQueue.global(qos: .utility).async {
            AppWorkspace.removeStaleWorkspaces()
        }
    }

    static func exitIfDuplicateInstance() {
        guard !isRunningTests else { return }
        switch acquireSingleInstanceLock() {
        case .acquired, .unavailable:
            return
        case .alreadyRunning(let lockURL, let processID):
            activateExistingInstance(lockURL: lockURL, processID: processID)
            _exit(78)
        }
    }

    static func singleInstanceLockURL(
        baseDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    ) -> URL {
        baseDirectory
            .appendingPathComponent("Upmarket", isDirectory: true)
            .appendingPathComponent("upmarket.lock")
    }

    static func singleInstanceLockURLs(
        appGroupContainerURL: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        applicationSupportDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    ) -> [URL] {
        let groupBase = (appGroupContainerURL ?? appGroupContainerFallbackURL(homeDirectory: homeDirectory))
            .appendingPathComponent("Application Support", isDirectory: true)

        return uniqueURLs([
            singleInstanceLockURL(baseDirectory: groupBase),
            singleInstanceLockURL(baseDirectory: applicationSupportDirectory)
        ])
    }

    static func acquireSingleInstanceLock(
        lockURLs: [URL] = singleInstanceLockURLs()
    ) -> SingleInstanceLockAcquisition {
        if singleInstanceLockFD >= 0 {
            return .acquired(acquiredSingleInstanceLockURL ?? singleInstanceLockURL())
        }

        for lockURL in lockURLs {
            switch acquireSingleInstanceLock(at: lockURL) {
            case .acquired:
                return .acquired(lockURL)
            case .alreadyRunning:
                return .alreadyRunning(lockURL, lockHolderPID(at: lockURL))
            case .unavailable:
                continue
            }
        }

        return .unavailable
    }

    private static func acquireSingleInstanceLock(at lockURL: URL) -> SingleInstanceLockAcquisition {
        do {
            try FileManager.default.createDirectory(
                at: lockURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return .unavailable
        }

        let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return .unavailable }

        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return .alreadyRunning(lockURL, lockHolderPID(at: lockURL))
        }

        singleInstanceLockFD = fd
        acquiredSingleInstanceLockURL = lockURL
        let pid = "\(getpid())\n"
        _ = ftruncate(fd, 0)
        _ = pid.withCString { write(fd, $0, strlen($0)) }
        return .acquired(lockURL)
    }

    static func releaseSingleInstanceLock() {
        guard singleInstanceLockFD >= 0 else { return }
        _ = flock(singleInstanceLockFD, LOCK_UN)
        close(singleInstanceLockFD)
        singleInstanceLockFD = -1
        acquiredSingleInstanceLockURL = nil
    }

    private static func appGroupContainerFallbackURL(homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Group Containers", isDirectory: true)
            .appendingPathComponent(appGroupID, isDirectory: true)
    }

    private static func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let key = url.standardizedFileURL.path
            if seen.insert(key).inserted {
                result.append(url)
            }
        }
        return result
    }

    private static func lockHolderPID(at lockURL: URL) -> pid_t? {
        guard let text = try? String(contentsOf: lockURL, encoding: .utf8),
              let value = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return value
    }

    private static func activateExistingInstance(lockURL: URL, processID: pid_t?) {
        if let processID,
           let app = NSRunningApplication(processIdentifier: processID) {
            app.activate(options: [.activateAllWindows])
            return
        }

        let bundleIdentifier = Bundle.main.bundleIdentifier
        NSWorkspace.shared.runningApplications
            .first { app in
                app.bundleIdentifier == bundleIdentifier && app.processIdentifier != getpid()
            }?
            .activate(options: [.activateAllWindows])
    }

    static func writeUITestWorkspacePathIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["UPMARKET_UI_TEST_WORKSPACE_PATH_FILE"],
              !path.isEmpty else { return }

        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? AppWorkspace.baseDirectory.path.write(to: url, atomically: true, encoding: .utf8)
    }
}
