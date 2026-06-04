import AppKit
import XCTest
@testable import Upmarket

final class DiagnosticsTests: XCTestCase {
    func testDiagnosticSnapshotIsJSONAndDoesNotIncludeSourcePath() throws {
        let snapshot = DiagnosticSnapshot(
            appVersion: "1.0",
            buildNumber: "42",
            macOSVersion: "macOS",
            hardwareModel: "Mac",
            localeIdentifier: "en_US",
            correlationID: UUID().uuidString,
            lastConversionStage: ConversionStage.failed.rawValue,
            lastErrorCode: "runtime.bridge",
            plistStatus: "ok",
            entitlementStatus: "sandboxed",
            modelManifestStatus: "not-installed"
        )

        let data = try Diagnostics.makeRedactedBundle(snapshot: snapshot)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("correlationID"))
        XCTAssertFalse(json.contains("/Users/"))
        XCTAssertFalse(json.contains("secret.pdf"))
    }

    func testPathRedactionKeepsOnlyLastComponent() {
        XCTAssertEqual(Diagnostics.redactPath("/Users/alice/Documents/secret.pdf"), "secret.pdf")
    }

    func testDiagnosticSnapshotUsesNeutralStageName() {
        let snapshot = Diagnostics.makeSnapshot(
            lastConversionStage: .python,
            lastErrorCode: "runtime.bridge"
        )

        XCTAssertEqual(snapshot.lastConversionStage, "Processing document")
        XCTAssertEqual(snapshot.lastErrorCode, "runtime.bridge")
    }

    func testDiagnosticSnapshotCanIncludeProductLevelProvenance() throws {
        let snapshot = Diagnostics.makeSnapshot(
            lastConversionStage: .complete,
            lastConversionPipeline: .enhanced,
            lastConversionPathway: .enhanced
        )

        let data = try Diagnostics.makeRedactedBundle(snapshot: snapshot)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(snapshot.lastConversionPipeline, "enhanced")
        XCTAssertEqual(snapshot.lastConversionPathway, "enhanced")
        XCTAssertTrue(json.contains(#""lastConversionPipeline":"enhanced""#))
        XCTAssertTrue(json.contains(#""lastConversionPathway":"enhanced""#))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("docling"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("python"))
    }

    func testWorkspaceCleanupRemovesDirectory() throws {
        let workspace = try AppWorkspace.create(prefix: "diagnostics-test")
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.path))

        AppWorkspace.remove(workspace)

        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.path))
    }

    func testStaleWorkspaceCleanupRemovesStartupLeftovers() throws {
        let workspace = try AppWorkspace.create(prefix: "diagnostics-stale-test")
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.path))

        AppWorkspace.removeStaleWorkspaces()

        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.path))
    }

    @MainActor
    func testAppDelegateTerminationCleansStaleWorkspaces() throws {
        let workspace = try AppWorkspace.create(prefix: "diagnostics-quit-test")
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.path))

        AppDelegate().applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.path))
    }

    func testAppProcessQuitAndRelaunchCleanAppWorkspaces() throws {
        let manager = FileManager.default
        let pathFile = manager.temporaryDirectory
            .appendingPathComponent("upmarket-process-workspace-\(UUID().uuidString).txt")
        defer { try? manager.removeItem(at: pathFile) }

        let firstLaunch = try launchAppProcess(workspacePathFile: pathFile)
        defer { terminate(firstLaunch) }

        let workspaceRoot = try waitForWorkspaceRoot(pathFile: pathFile)
        try? manager.removeItem(at: workspaceRoot)
        try manager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: workspaceRoot) }

        let quitSentinel = try createSentinelWorkspace(named: "process-quit-cleanup", in: workspaceRoot)
        firstLaunch.terminate()
        XCTAssertTrue(waitUntil(timeout: 5) {
            !firstLaunch.isRunning && !manager.fileExists(atPath: quitSentinel.path)
        })

        let relaunchSentinel = try createSentinelWorkspace(named: "process-relaunch-cleanup", in: workspaceRoot)
        let secondLaunch = try launchAppProcess(workspacePathFile: pathFile)
        defer { terminate(secondLaunch) }

        _ = try waitForWorkspaceRoot(pathFile: pathFile)
        XCTAssertTrue(waitUntil(timeout: 5) {
            !manager.fileExists(atPath: relaunchSentinel.path)
        })
    }

    func testOversizedInputIsRejectedBeforeCopy() throws {
        let input = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        FileManager.default.createFile(atPath: input.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: input) }
        let handle = try FileHandle(forWritingTo: input)
        try handle.truncate(atOffset: UInt64(AppWorkspace.maxInputBytes + 1))
        try handle.close()

        let workspace = try AppWorkspace.create(prefix: "diagnostics-test")
        defer { AppWorkspace.remove(workspace) }

        XCTAssertThrowsError(try AppWorkspace.copy(input, into: workspace)) { error in
            XCTAssertEqual(error as? ConversionError, .fileTooLarge)
        }
    }

    private func launchAppProcess(workspacePathFile: URL) throws -> Process {
        let executable = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/Upmarket")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw XCTSkip("Upmarket executable is not available in the test host bundle")
        }

        let process = Process()
        process.executableURL = executable
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": NSHomeDirectory(),
            "TMPDIR": FileManager.default.temporaryDirectory.path,
            "XCTestConfigurationFilePath": "UpmarketProcessLifecycleTest",
            "UPMARKET_UI_TEST_WORKSPACE_PATH_FILE": workspacePathFile.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    private func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        _ = waitUntil(timeout: 3) {
            !process.isRunning
        }
        if process.isRunning {
            process.interrupt()
        }
    }

    private func createSentinelWorkspace(named prefix: String, in root: URL) throws -> URL {
        let workspace = root.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try Data("stale workspace sentinel".utf8).write(to: workspace.appendingPathComponent("sentinel.txt"))
        return workspace
    }

    private func waitForWorkspaceRoot(pathFile: URL) throws -> URL {
        let manager = FileManager.default
        var value = ""
        XCTAssertTrue(waitUntil(timeout: 5) {
            guard manager.fileExists(atPath: pathFile.path),
                  let text = try? String(contentsOf: pathFile, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return true
        })
        return URL(fileURLWithPath: value, isDirectory: true)
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }
}
