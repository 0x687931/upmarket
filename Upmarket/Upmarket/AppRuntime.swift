import Foundation
import Darwin

enum AppRuntime {
    private static var terminationSignalSources: [DispatchSourceSignal] = []
    private static var singleInstanceLockFD: CInt = -1

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
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

    static func exitIfDuplicateInstance() {
        guard !isRunningTests else { return }
        guard !acquireSingleInstanceLock() else { return }

        _exit(78)
    }

    static func singleInstanceLockURL(
        baseDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    ) -> URL {
        baseDirectory
            .appendingPathComponent("Upmarket", isDirectory: true)
            .appendingPathComponent("upmarket.lock")
    }

    private static func acquireSingleInstanceLock() -> Bool {
        if singleInstanceLockFD >= 0 { return true }

        let lockURL = singleInstanceLockURL()
        do {
            try FileManager.default.createDirectory(
                at: lockURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            return true
        }

        let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { return true }

        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return false
        }

        singleInstanceLockFD = fd
        let pid = "\(getpid())\n"
        _ = ftruncate(fd, 0)
        _ = pid.withCString { write(fd, $0, strlen($0)) }
        return true
    }

    private static func releaseSingleInstanceLock() {
        guard singleInstanceLockFD >= 0 else { return }
        _ = flock(singleInstanceLockFD, LOCK_UN)
        close(singleInstanceLockFD)
        singleInstanceLockFD = -1
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
