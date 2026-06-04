import AppKit
import XCTest
@testable import Upmarket

final class AppVisibilityPreferenceTests: XCTestCase {
    func testSingleInstanceLockURLUsesApplicationSupport() {
        let base = URL(fileURLWithPath: "/tmp/upmarket-tests/Application Support")

        let url = AppRuntime.singleInstanceLockURL(baseDirectory: base)

        XCTAssertEqual(url.path, "/tmp/upmarket-tests/Application Support/Upmarket/upmarket.lock")
    }

    func testActivationPolicyMapsDockPreference() {
        XCTAssertEqual(
            AppVisibilityPreference.activationPolicy(showDockIcon: false),
            .accessory
        )
        XCTAssertEqual(
            AppVisibilityPreference.activationPolicy(showDockIcon: true),
            .regular
        )
    }

    func testDockPreferencePersistsInUserDefaults() {
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
        XCTAssertFalse(defaults.bool(forKey: AppVisibilityPreference.showDockIconKey))
    }
}
