import Foundation
import Darwin

enum AppRuntime {
    private static var terminationSignalSources: [DispatchSourceSignal] = []

    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static func installTerminationSignalCleanup() {
        guard terminationSignalSources.isEmpty else { return }

        for signalNumber in [SIGTERM, SIGINT] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                AppWorkspace.removeStaleWorkspaces()
                exit(0)
            }
            source.resume()
            terminationSignalSources.append(source)
        }
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
