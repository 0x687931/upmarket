import AppKit
import Foundation

enum AppVisibilityPreference {
    static let showDockIconKey = "upmarket.showDockIcon"
    static let defaultShowDockIcon = false

    static var showDockIcon: Bool {
        get { UserDefaults.standard.bool(forKey: showDockIconKey) }
        set { UserDefaults.standard.set(newValue, forKey: showDockIconKey) }
    }

    static func activationPolicy(showDockIcon: Bool) -> NSApplication.ActivationPolicy {
        showDockIcon ? .regular : .accessory
    }

    @MainActor
    static func apply() {
        apply(showDockIcon: showDockIcon)
    }

    @MainActor
    static func apply(showDockIcon: Bool) {
        NSApp.setActivationPolicy(activationPolicy(showDockIcon: showDockIcon))
    }
}
