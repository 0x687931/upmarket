import AppKit
import Darwin
import XCTest
@testable import Upmarket

final class AppVisibilityPreferenceTests: XCTestCase {
    func testMenuBarHashTemplateAssetLoads() {
        // The menu bar draws the monochrome MenuBarHash template (the Y-rotated `#`).
        XCTAssertNotNil(NSImage(named: "MenuBarHash"))
    }

    func testSingleInstanceLockURLUsesApplicationSupport() {
        let base = URL(fileURLWithPath: "/tmp/upmarket-tests/Application Support")

        let url = AppRuntime.singleInstanceLockURL(baseDirectory: base)

        XCTAssertEqual(url.path, "/tmp/upmarket-tests/Application Support/Upmarket/upmarket.lock")
    }

    func testSingleInstanceLockPrefersSharedAppGroupLocation() {
        let home = URL(fileURLWithPath: "/tmp/upmarket-tests/home", isDirectory: true)
        let appSupport = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let appGroup = URL(fileURLWithPath: "/tmp/upmarket-tests/Group Containers/group.com.upmarket.app", isDirectory: true)

        let urls = AppRuntime.singleInstanceLockURLs(
            appGroupContainerURL: appGroup,
            homeDirectory: home,
            applicationSupportDirectory: appSupport
        )

        XCTAssertEqual(
            urls.map(\.path),
            [
                "/tmp/upmarket-tests/Group Containers/group.com.upmarket.app/Application Support/Upmarket/upmarket.lock",
                "/tmp/upmarket-tests/home/Library/Application Support/Upmarket/upmarket.lock"
            ]
        )
    }

    func testSingleInstanceLockFallsBackToWellKnownGroupContainerForUnsignedBuilds() {
        let home = URL(fileURLWithPath: "/tmp/upmarket-tests/home", isDirectory: true)
        let appSupport = home.appendingPathComponent("Library/Application Support", isDirectory: true)

        let urls = AppRuntime.singleInstanceLockURLs(
            appGroupContainerURL: nil,
            homeDirectory: home,
            applicationSupportDirectory: appSupport
        )

        XCTAssertEqual(
            urls.first?.path,
            "/tmp/upmarket-tests/home/Library/Group Containers/group.com.upmarket.app/Application Support/Upmarket/upmarket.lock"
        )
    }

    func testSingleInstanceLockRejectsSecondHolder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpmarketSingleInstance-\(UUID().uuidString)", isDirectory: true)
        let lockURL = AppRuntime.singleInstanceLockURL(baseDirectory: root)
        defer {
            AppRuntime.releaseSingleInstanceLock()
            try? FileManager.default.removeItem(at: root)
        }

        let first = AppRuntime.acquireSingleInstanceLock(lockURLs: [lockURL])
        guard case .acquired(let acquiredURL) = first else {
            return XCTFail("Expected first lock acquisition to succeed")
        }
        XCTAssertEqual(acquiredURL, lockURL)

        let competingFD = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        XCTAssertGreaterThanOrEqual(competingFD, 0)
        defer { close(competingFD) }

        XCTAssertNotEqual(flock(competingFD, LOCK_EX | LOCK_NB), 0)
    }

    func testActivationPolicyMapsDockPreference() {
        XCTAssertEqual(
            AppVisibilityPreference.activationPolicy(showDockIcon: false),
            .regular
        )
        XCTAssertEqual(
            AppVisibilityPreference.activationPolicy(showDockIcon: true),
            .regular
        )
    }

    func testDockPreferenceIsForcedOnForInterfaceRecovery() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: AppVisibilityPreference.showDockIconKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: AppVisibilityPreference.showDockIconKey)
            } else {
                defaults.removeObject(forKey: AppVisibilityPreference.showDockIconKey)
            }
        }

        defaults.removeObject(forKey: AppVisibilityPreference.showDockIconKey)
        XCTAssertTrue(AppVisibilityPreference.showDockIcon)

        AppVisibilityPreference.showDockIcon = true
        XCTAssertTrue(defaults.bool(forKey: AppVisibilityPreference.showDockIconKey))

        AppVisibilityPreference.showDockIcon = false
        XCTAssertTrue(AppVisibilityPreference.showDockIcon)
        XCTAssertTrue(defaults.bool(forKey: AppVisibilityPreference.showDockIconKey))

        defaults.set(false, forKey: AppVisibilityPreference.showDockIconKey)
        AppVisibilityPreference.normalizePersistentVisibility()
        XCTAssertTrue(AppVisibilityPreference.showDockIcon)
        XCTAssertTrue(defaults.bool(forKey: AppVisibilityPreference.showDockIconKey))
    }

    func testMenuBarAndShelfPreferencesPersistIndependently() {
        let defaults = UserDefaults.standard
        let previousMenu = defaults.object(forKey: AppVisibilityPreference.showMenuBarIconKey)
        let previousShelf = defaults.object(forKey: AppVisibilityPreference.showShelfKey)
        defer {
            if let previousMenu {
                defaults.set(previousMenu, forKey: AppVisibilityPreference.showMenuBarIconKey)
            } else {
                defaults.removeObject(forKey: AppVisibilityPreference.showMenuBarIconKey)
            }
            if let previousShelf {
                defaults.set(previousShelf, forKey: AppVisibilityPreference.showShelfKey)
            } else {
                defaults.removeObject(forKey: AppVisibilityPreference.showShelfKey)
            }
        }

        AppVisibilityPreference.showMenuBarIcon = false
        AppVisibilityPreference.showShelf = false

        XCTAssertFalse(AppVisibilityPreference.showMenuBarIcon)
        XCTAssertFalse(AppVisibilityPreference.showShelf)

        AppVisibilityPreference.showMenuBarIcon = true
        AppVisibilityPreference.showShelf = true

        XCTAssertTrue(AppVisibilityPreference.showMenuBarIcon)
        XCTAssertTrue(AppVisibilityPreference.showShelf)
    }
}
