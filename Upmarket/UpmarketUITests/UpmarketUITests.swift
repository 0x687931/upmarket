//
//  UpmarketUITests.swift
//  UpmarketUITests
//
//  Created by Andrew McArdle on 30/5/2026.
//

import XCTest

final class UpmarketUITests: XCTestCase {
    private var cleanupURLs: [URL] = []
    private var launchedApps: [XCUIApplication] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIApplication().terminate()
    }

    override func tearDownWithError() throws {
        for app in launchedApps {
            app.terminate()
        }
        launchedApps.removeAll()
        for url in cleanupURLs {
            try? FileManager.default.removeItem(at: url)
        }
        cleanupURLs.removeAll()
    }

    @MainActor
    func testPrimaryConversionWindowIsMounted() throws {
        let app = makeApp()
        app.launch()

        let primaryView = app.descendants(matching: .any)["PrimaryConversionView"]
        XCTAssertTrue(primaryView.waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.descendants(matching: .any)["ChooseDocumentButton"].waitForExistence(timeout: 3)
                || app.buttons["Choose File"].waitForExistence(timeout: 3)
        )
    }

    @MainActor
    func testGUIQuitAndRelaunchCleanAppWorkspaces() throws {
        let manager = FileManager.default
        let pathFile = manager.temporaryDirectory
            .appendingPathComponent("upmarket-ui-workspace-\(UUID().uuidString).txt")
        cleanupURLs.append(pathFile)

        let app = makeApp()
        app.launchEnvironment["UPMARKET_UI_TEST_WORKSPACE_PATH_FILE"] = pathFile.path
        launchedApps.append(app)
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["PrimaryConversionView"].waitForExistence(timeout: 3))

        let workspaceRoot = try waitForWorkspaceRoot(pathFile: pathFile)
        cleanupURLs.append(workspaceRoot)
        try? manager.removeItem(at: workspaceRoot)
        try manager.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        let quitSentinel = try createSentinelWorkspace(named: "ui-quit-cleanup", in: workspaceRoot)

        app.terminate()
        XCTAssertTrue(waitUntil(timeout: 5) {
            !manager.fileExists(atPath: quitSentinel.path)
        })

        let relaunchSentinel = try createSentinelWorkspace(named: "ui-relaunch-cleanup", in: workspaceRoot)

        let relaunched = makeApp()
        relaunched.launchEnvironment["UPMARKET_UI_TEST_WORKSPACE_PATH_FILE"] = pathFile.path
        launchedApps.append(relaunched)
        relaunched.launch()
        XCTAssertTrue(relaunched.descendants(matching: .any)["PrimaryConversionView"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitUntil(timeout: 5) {
            !manager.fileExists(atPath: relaunchSentinel.path)
        })
        relaunched.terminate()
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["UPMARKET_UI_TESTING"] = "1"
        return app
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
