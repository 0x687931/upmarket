import AppKit
import Foundation

enum AppVisibilityPreference {
    static let showDockIconKey = "upmarket.showDockIcon"
    static let defaultShowDockIcon = true

    static var showDockIcon: Bool {
        get {
            guard let value = UserDefaults.standard.object(forKey: showDockIconKey) as? Bool else {
                return defaultShowDockIcon
            }
            return value
        }
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
