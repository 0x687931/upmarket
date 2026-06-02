//
//  UpmarketUITests.swift
//  UpmarketUITests
//
//  Created by Andrew McArdle on 30/5/2026.
//

import XCTest

final class UpmarketUITests: XCTestCase {
    private var cleanupURLs: [URL] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        for url in cleanupURLs {
            try? FileManager.default.removeItem(at: url)
        }
        cleanupURLs.removeAll()
    }

    @MainActor
    func testPrimaryConversionWindowIsMounted() throws {
        let app = XCUIApplication()
        app.launch()

        let primaryView = app.descendants(matching: .any)["PrimaryConversionView"]
        XCTAssertTrue(primaryView.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["ChooseDocumentButton"].exists)
    }

    @MainActor
    func testGUIQuitAndRelaunchCleanAppWorkspaces() throws {
        let manager = FileManager.default
        let workspaceRoots = candidateWorkspaceRoots()
        XCTAssertFalse(workspaceRoots.isEmpty)
        cleanupURLs.append(contentsOf: workspaceRoots)

        for root in workspaceRoots {
            try? manager.removeItem(at: root)
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
        }

        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["PrimaryConversionView"].waitForExistence(timeout: 3))

        let quitSentinels = try workspaceRoots.map { root in
            try createSentinelWorkspace(named: "ui-quit-cleanup", in: root)
        }

        app.terminate()
        XCTAssertTrue(waitUntil(timeout: 5) {
            quitSentinels.contains { !manager.fileExists(atPath: $0.path) }
        })

        let activeRoot = try XCTUnwrap(quitSentinels.first { !manager.fileExists(atPath: $0.path) }?.deletingLastPathComponent())
        let relaunchSentinel = try createSentinelWorkspace(named: "ui-relaunch-cleanup", in: activeRoot)

        let relaunched = XCUIApplication()
        relaunched.launch()
        XCTAssertTrue(relaunched.descendants(matching: .any)["PrimaryConversionView"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitUntil(timeout: 5) {
            !manager.fileExists(atPath: relaunchSentinel.path)
        })
        relaunched.terminate()
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    private func candidateWorkspaceRoots() -> [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return [
            home
                .appendingPathComponent("Library/Application Support/Upmarket/Workspaces", isDirectory: true),
            home
                .appendingPathComponent("Library/Containers/com.upmarket.app/Data/Library/Application Support/Upmarket/Workspaces", isDirectory: true)
        ]
    }

    private func createSentinelWorkspace(named prefix: String, in root: URL) throws -> URL {
        let workspace = root.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try Data("stale workspace sentinel".utf8).write(to: workspace.appendingPathComponent("sentinel.txt"))
        return workspace
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
