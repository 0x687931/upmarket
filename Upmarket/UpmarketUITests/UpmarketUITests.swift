//
//  UpmarketUITests.swift
//  UpmarketUITests
//
//  Created by Andrew McArdle on 30/5/2026.
//

import XCTest

final class UpmarketUITests: XCTestCase {
    private let targetBundleIdentifier = "com.upmarket.app"
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
        let pathFile = try targetAppWritableTemporaryFile(
            named: "upmarket-ui-workspace-\(UUID().uuidString).txt"
        )
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

    // MARK: - Content window

    @MainActor
    func testContentViewChooseDocumentButton() throws {
        let app = makeApp()
        app.launch()

        let primaryView = app.descendants(matching: .any)["PrimaryConversionView"]
        XCTAssertTrue(primaryView.waitForExistence(timeout: 3))

        let chooseButton = app.buttons.matching(identifier: "ChooseDocumentButton").firstMatch
        XCTAssertTrue(chooseButton.waitForExistence(timeout: 3))
        XCTAssertTrue(chooseButton.isEnabled)
        XCTAssertTrue(chooseButton.isHittable)

        let dropZone = app.descendants(matching: .any).matching(identifier: "ContentDropZone").firstMatch
        XCTAssertTrue(dropZone.waitForExistence(timeout: 3))
        XCTAssertTrue(dropZone.isHittable)
    }

    // MARK: - Paywall

    @MainActor
    func testPaywallTierSelectionChanges() throws {
        let app = makeApp()
        app.launchEnvironment["UPMARKET_UI_TEST_OPEN_PAYWALL"] = "1"
        app.launch()

        let basicCard = app.buttons.matching(identifier: "PaywallBasicTierCard").firstMatch
        XCTAssertTrue(basicCard.waitForExistence(timeout: 3), "Basic tier card must appear")
        XCTAssertTrue(basicCard.isHittable, "Basic tier card must be hittable")

        let proCard = app.buttons.matching(identifier: "PaywallProTierCard").firstMatch
        guard proCard.exists else {
            // AI not available on this device: only the basic card is shown and already selected.
            XCTAssertEqual(basicCard.value as? String, "selected",
                           "Basic card must already be selected when it is the only option")
            return
        }

        // Both cards are present — pro starts selected.
        XCTAssertEqual(proCard.value as? String, "selected",
                       "Pro card must start selected when AI is available")
        XCTAssertEqual(basicCard.value as? String, "deselected",
                       "Basic card must start deselected when pro is the default")

        basicCard.tap()

        XCTAssertTrue(
            waitUntil(timeout: 3) { basicCard.value as? String == "selected" },
            "Basic card must become selected after tap"
        )
        XCTAssertEqual(proCard.value as? String, "deselected",
                       "Pro card must become deselected after selecting basic")
    }

    @MainActor
    func testPaywallCTAAndRestoreButtonsPresent() throws {
        let app = makeApp()
        app.launchEnvironment["UPMARKET_UI_TEST_OPEN_PAYWALL"] = "1"
        app.launch()

        let basicCard = app.buttons.matching(identifier: "PaywallBasicTierCard").firstMatch
        XCTAssertTrue(basicCard.waitForExistence(timeout: 3))

        let cta = app.buttons.matching(identifier: "PaywallCTAButton").firstMatch
        XCTAssertTrue(cta.waitForExistence(timeout: 3), "CTA button must be present")

        let restore = app.buttons.matching(identifier: "PaywallRestoreButton").firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 3), "Restore button must be present")
        XCTAssertTrue(restore.isHittable, "Restore button must be hittable")
    }

    // MARK: - Preferences

    @MainActor
    func testPreferencesInteractiveControls() throws {
        let app = makeApp()
        app.launchEnvironment["UPMARKET_UI_TEST_OPEN_PREFERENCES"] = "1"
        app.launch()

        let dockToggle = app.descendants(matching: .checkBox)
            .matching(identifier: "PrefsDockIconToggle").firstMatch
        XCTAssertTrue(dockToggle.waitForExistence(timeout: 3), "Dock icon toggle must appear")
        XCTAssertTrue(dockToggle.isHittable, "Dock icon toggle must be hittable")

        let menuBarToggle = app.descendants(matching: .checkBox)
            .matching(identifier: "PrefsMenuBarIconToggle").firstMatch
        XCTAssertTrue(menuBarToggle.waitForExistence(timeout: 3), "Menu bar icon toggle must appear")
        XCTAssertTrue(menuBarToggle.isHittable, "Menu bar icon toggle must be hittable")

        let restoreButton = app.buttons.matching(identifier: "PrefsRestorePurchasesButton").firstMatch
        XCTAssertTrue(restoreButton.waitForExistence(timeout: 3), "Restore Purchases button must appear")
        XCTAssertTrue(restoreButton.isHittable, "Restore Purchases button must be hittable")
    }

    // MARK: - Shelf

    @MainActor
    func testShelfControlStripButtons() throws {
        let app = makeApp()
        app.launchEnvironment["UPMARKET_UI_TEST_OPEN_SHELF"] = "1"
        app.launch()

        // The shelf starts in mini mode; tap to expand to peek mode.
        let miniShelf = app.buttons.matching(identifier: "ShelfMini").firstMatch
        XCTAssertTrue(miniShelf.waitForExistence(timeout: 3), "Mini shelf must appear")
        XCTAssertTrue(miniShelf.isHittable, "Mini shelf must be hittable")
        miniShelf.tap()

        // Control strip buttons become visible once the shelf is in peek mode.
        let closeButton = app.buttons.matching(identifier: "ShelfCloseButton").firstMatch
        XCTAssertTrue(closeButton.waitForExistence(timeout: 2), "Shelf close button must appear after expansion")
        XCTAssertTrue(closeButton.isHittable)

        let addButton = app.buttons.matching(identifier: "ShelfAddButton").firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 2), "Shelf add button must appear after expansion")
        XCTAssertTrue(addButton.isHittable)

        let toggleButton = app.buttons.matching(identifier: "ShelfToggleButton").firstMatch
        XCTAssertTrue(toggleButton.waitForExistence(timeout: 2), "Shelf toggle button must appear after expansion")
        XCTAssertTrue(toggleButton.isHittable)

        // Tapping close must dismiss the control strip (shelf returns to mini or hides).
        closeButton.tap()
        XCTAssertTrue(
            waitUntil(timeout: 2) { !closeButton.exists },
            "Close button must disappear after tapping shelf close"
        )
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["UPMARKET_UI_TESTING"] = "1"
        return app
    }

    private func targetAppWritableTemporaryFile(named name: String) throws -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(targetBundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data/tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name, isDirectory: false)
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
