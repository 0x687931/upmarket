import AppKit
import Foundation

enum AppVisibilityPreference {
    static let showDockIconKey = "upmarket.showDockIcon"
    static let showMenuBarIconKey = "upmarket.showMenuBarIcon"
    static let showShelfKey = "upmarket.showShelf"
    static let defaultShowDockIcon = true
    static let defaultShowMenuBarIcon = true
    static let defaultShowShelf = false
    static let requiresDockIcon = true

    static var showDockIcon: Bool {
        get {
            if requiresDockIcon {
                return true
            }
            guard let value = UserDefaults.standard.object(forKey: showDockIconKey) as? Bool else {
                return defaultShowDockIcon
            }
            return value
        }
        set { UserDefaults.standard.set(requiresDockIcon ? true : newValue, forKey: showDockIconKey) }
    }

    static var showMenuBarIcon: Bool {
        get {
            guard let value = UserDefaults.standard.object(forKey: showMenuBarIconKey) as? Bool else {
                return defaultShowMenuBarIcon
            }
            return value
        }
        set { UserDefaults.standard.set(newValue, forKey: showMenuBarIconKey) }
    }

    static var showShelf: Bool {
        get {
            guard let value = UserDefaults.standard.object(forKey: showShelfKey) as? Bool else {
                return defaultShowShelf
            }
            return value
        }
        set { UserDefaults.standard.set(newValue, forKey: showShelfKey) }
    }

    static func activationPolicy(showDockIcon: Bool) -> NSApplication.ActivationPolicy {
        requiresDockIcon || showDockIcon ? .regular : .accessory
    }

    static func normalizePersistentVisibility() {
        if requiresDockIcon {
            showDockIcon = true
            return
        }
        if !showDockIcon && !showMenuBarIcon {
            showMenuBarIcon = true
        }
    }

    @MainActor
    static func apply() {
        normalizePersistentVisibility()
        apply(showDockIcon: showDockIcon)
        applyMenuBarVisibility(showMenuBarIcon: showMenuBarIcon)
    }

    @MainActor
    static func apply(showDockIcon: Bool) {
        self.showDockIcon = showDockIcon
        NSApp.setActivationPolicy(activationPolicy(showDockIcon: self.showDockIcon))
    }

    @MainActor
    static func applyMenuBarVisibility(showMenuBarIcon: Bool) {
        self.showMenuBarIcon = showMenuBarIcon
        MenuBarStatusController.shared.applyVisibility(show: showMenuBarIcon)
    }

    @MainActor
    static func applyShelfVisibility(showShelf: Bool) {
        self.showShelf = showShelf
        if showShelf {
            ShelfWindowController.shared.show(animate: true, ignoringPreference: true)
        } else {
            ShelfWindowController.shared.hide()
        }
    }
}
