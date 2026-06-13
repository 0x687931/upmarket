import AppKit
import Combine
import SwiftUI

private struct QuickActionHandoff: Decodable {
    let files: [String]
}

struct QuickActionHandoffFile {
    let fileURL: URL
    let handoffDirectory: URL
}

/// AppDelegate handles app lifecycle, URL scheme handling (from Quick Action),
/// and Services menu integration.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var progressCancellable: AnyCancellable?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false  // Stay alive as menu bar + shelf app
    }

    func applicationWillTerminate(_ notification: Notification) {
        ConversionQueue.shared.cancelAll()
        AppWorkspace.removeStaleWorkspaces()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLaunchMetrics.mark("didFinishLaunching")
        AppVisibilityPreference.apply()
        if AppRuntime.isRunningUITests {
            MainWindowController.shared.show()
            if AppRuntime.isOpeningPaywall {
                PaywallWindowController.shared.show()
            }
            if AppRuntime.isOpeningPreferences {
                PreferencesWindowController.shared.show()
            }
            if AppRuntime.isOpeningShelf {
                AppVisibilityPreference.showShelf = true
                ShelfWindowController.shared.show(ignoringPreference: true)
            }
        }

        NSApp.servicesProvider = self
        MemoryPressureMonitor.shared.start()
        if !AppRuntime.isRunningTests {
            ConversionHistoryStore.shared.loadDeferred()
        }
        AppLaunchMetrics.mark("post-launch-services")
        DispatchQueue.global(qos: .utility).async {
            Self.removeStaleQuickActionHandoffs()
            BundledModelService.installBundledModelsIfNeeded()
        }

        // Observe conversion state for Dock tile animation
        NotificationCenter.default.addObserver(
            self, selector: #selector(conversionStarted),
            name: .upmarketConversionStarted, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(conversionEnded),
            name: .upmarketConversionEnded, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(showPaywall),
            name: .showPaywall, object: nil
        )
    }

    @objc private func conversionStarted() {
        ConversionIconLayerView.startDockAnimation()
        MenuBarStatusController.shared.refresh()
        progressCancellable = ConversionQueue.shared.$jobs
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateDockProgress()
            }
    }

    @objc private func conversionEnded() {
        progressCancellable = nil
        ConversionIconLayerView.stopDockAnimation()
        MenuBarStatusController.shared.refresh()
    }

    private func updateDockProgress() {
        let progress = ConversionQueue.shared.overallProgress
        ConversionIconLayerView.updateDockProgress(progress)
    }

    @objc private func showPaywall() {
        Task { @MainActor in
            PaywallWindowController.shared.show()
        }
    }

    // MARK: - Dock menu

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu(title: "Upmarket")

        if ConversionQueue.shared.isConverting {
            let percent = Int((ConversionQueue.shared.overallProgress * 100).rounded())
            let title = percent > 0 ? "Converting \(percent)%" : "Converting…"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        }

        menu.addItem(dockMenuItem(title: "Convert Document…", action: #selector(dockConvertDocument(_:))))
        menu.addItem(dockMenuItem(title: "Show Upmarket Window", action: #selector(dockShowMainWindow(_:))))
        #if DEBUG
        menu.addItem(dockMenuItem(title: shelfDockTitle, action: #selector(dockShowShelf(_:))))
        #endif

        menu.addItem(.separator())

        menu.addItem(dockMenuItem(title: "Preferences…", action: #selector(dockShowPreferences(_:))))

        return menu
    }

    private var shelfDockTitle: String {
        let count = ConversionQueue.shared.jobs.count
        return count > 0 ? "Show Shelf (\(count))" : "Show Shelf"
    }

    private func dockMenuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func dockConvertDocument(_ sender: Any?) {
        MainWindowController.shared.show(pickFile: true)
    }

    @objc private func dockShowMainWindow(_ sender: Any?) {
        MainWindowController.shared.show()
    }

    @objc private func dockShowShelf(_ sender: Any?) {
        AppVisibilityPreference.showShelf = true
        ShelfWindowController.shared.show(ignoringPreference: true)
    }

    @objc private func dockShowPreferences(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        PreferencesWindowController.shared.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showPreferredConversionSurface()
        return false
    }

    // MARK: - URL Scheme handler (from Quick Action extension and CLI)
    // upmarket://convert?handoff=<uuid>
    // upmarket://convert?cli=<uuid>

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard url.scheme == "upmarket", url.host == "convert",
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else { continue }

            if let cliID = components.queryItems?.first(where: { $0.name == "cli" })?.value {
                CLIConversionBroker.live()?.handle(id: cliID)
            } else if let handoffID = components.queryItems?.first(where: { $0.name == "handoff" })?.value {
                openQuickActionHandoff(id: handoffID)
            }
        }
    }

    private func openQuickActionHandoff(id: String) {
        guard UUID(uuidString: id) != nil,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.upmarket.app")
        else { return }

        let handoffDirectory = container
            .appendingPathComponent("QuickActionHandoffs", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
        let manifestURL = handoffDirectory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let handoff = try? JSONDecoder().decode(QuickActionHandoff.self, from: data)
        else { return }

        showPreferredConversionSurface()
        for fileName in handoff.files where !fileName.contains("/") {
            NotificationCenter.default.post(
                name: .upmarketConvertFile,
                object: QuickActionHandoffFile(
                    fileURL: handoffDirectory.appendingPathComponent(fileName),
                    handoffDirectory: handoffDirectory
                )
            )
        }
    }

    nonisolated private static func removeStaleQuickActionHandoffs() {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.upmarket.app") else {
            return
        }
        let root = container.appendingPathComponent("QuickActionHandoffs", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            guard values?.isDirectory == true,
                  (values?.contentModificationDate ?? .distantPast) < cutoff else { continue }
            try? FileManager.default.removeItem(at: entry)
        }
    }

    // MARK: - Services menu handler

    @objc func convertToMarkdown(_ pasteboard: NSPasteboard,
                                  userData: String?,
                                  error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        guard let items = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !items.isEmpty else { return }

        showPreferredConversionSurface()
        for url in items {
            NotificationCenter.default.post(name: .upmarketConvertFile, object: url)
        }
    }

    private func showPreferredConversionSurface() {
        if AppVisibilityPreference.showShelf {
            ShelfWindowController.shared.show()
        } else {
            MainWindowController.shared.show()
        }
    }
}

extension Notification.Name {
    static let upmarketConvertFile = Notification.Name("upmarket.convertFile")
}

@MainActor
private enum MenuBarStatusIcon {
    private static let convertingTint = NSColor(srgbRed: 0.91, green: 0.47, blue: 0.0, alpha: 1)
    private static let iconSize = NSSize(width: 22, height: 22)
    private static let glyphSize = NSSize(width: 18, height: 18)
    private static let badgeSize = NSSize(width: 6, height: 6)

    static func image(isConverting: Bool) -> NSImage {
        guard let hash = NSImage(named: "MenuBarHash") else {
            return NSImage(size: iconSize)
        }

        guard isConverting else {
            // Monochrome template — macOS tints it for light/dark menu bars and
            // dims/highlights it when the menu is open, like other menu bar apps.
            hash.isTemplate = true
            return hash
        }

        let composed = NSImage(size: iconSize)
        composed.lockFocus()

        let glowRect = NSRect(
            x: 8,
            y: 4,
            width: 10,
            height: 10
        )
        convertingTint.withAlphaComponent(0.12).setFill()
        NSBezierPath(ovalIn: glowRect).fill()

        let glyphRect = NSRect(
            x: (iconSize.width - glyphSize.width) / 2,
            y: (iconSize.height - glyphSize.height) / 2,
            width: glyphSize.width,
            height: glyphSize.height
        )
        hash.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1)

        let badgeRect = NSRect(
            x: iconSize.width - badgeSize.width - 2,
            y: 2,
            width: badgeSize.width,
            height: badgeSize.height
        )
        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()
        NSColor.white.setStroke()
        let badgePath = NSBezierPath(ovalIn: badgeRect)
        badgePath.lineWidth = 1
        badgePath.stroke()

        composed.unlockFocus()
        composed.isTemplate = false
        return composed
    }
}

@MainActor
final class MenuBarStatusController: NSObject, NSMenuDelegate {
    static let shared = MenuBarStatusController()

    private var statusItem: NSStatusItem?
    private lazy var menu: NSMenu = {
        let menu = NSMenu(title: "Upmarket")
        menu.delegate = self
        return menu
    }()

    private override init() {
        super.init()
    }

    func applyVisibility(show: Bool) {
        if show {
            install()
        } else {
            remove()
        }
    }

    func refresh() {
        updateIcon()
    }

    private func install() {
        guard statusItem == nil else {
            updateIcon()
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = menu
        statusItem = item
        updateIcon()
    }

    private func remove() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        button.image = MenuBarStatusIcon.image(isConverting: ConversionQueue.shared.isConverting)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "Upmarket"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateIcon()
        menu.removeAllItems()

        if ConversionQueue.shared.isConverting {
            let percent = Int((ConversionQueue.shared.overallProgress * 100).rounded())
            let title = percent > 0 ? "Converting \(percent)%" : "Converting…"
            menu.addItem(disabledItem(title))
            menu.addItem(.separator())
        }

        menu.addItem(actionItem(
            title: "Convert Document…",
            systemImage: "doc.badge.plus",
            action: #selector(convertDocument(_:)),
            keyEquivalent: "o",
            modifiers: [.command]
        ))
        menu.addItem(actionItem(
            title: "Show Upmarket Window",
            systemImage: "macwindow",
            action: #selector(showMainWindow(_:))
        ))
        menu.addItem(actionItem(
            title: shelfToggleTitle,
            systemImage: "square.grid.2x2",
            action: #selector(showShelf(_:)),
            keyEquivalent: "s",
            modifiers: [.command, .shift]
        ))

        menu.addItem(.separator())

        menu.addItem(actionItem(
            title: "Preferences…",
            systemImage: "gearshape",
            action: #selector(showPreferences(_:)),
            keyEquivalent: ",",
            modifiers: [.command]
        ))
        menu.addItem(actionItem(
            title: "Report a Problem…",
            systemImage: "exclamationmark.bubble",
            action: #selector(showReportProblem(_:))
        ))

        menu.addItem(.separator())

        switch StoreManager.shared.tier {
        case .max:
            menu.addItem(statusItem(title: entitlementTitle, systemImage: "checkmark.circle"))
        case .pro:
            menu.addItem(actionItem(
                title: "Upgrade to Upmarket Max…",
                systemImage: "arrow.up.circle",
                action: #selector(showPaywall(_:))
            ))
        case .basic:
            menu.addItem(actionItem(
                title: "Upgrade to Upmarket Pro…",
                systemImage: "arrow.up.circle",
                action: #selector(showPaywall(_:))
            ))
        }

        menu.addItem(.separator())

        menu.addItem(actionItem(
            title: "Quit Upmarket",
            systemImage: "power",
            action: #selector(quit(_:)),
            keyEquivalent: "q",
            modifiers: [.command]
        ))
    }

    private var shelfToggleTitle: String {
        AppVisibilityPreference.showShelf ? "Hide Shelf" : "Show Shelf"
    }

    private var entitlementTitle: String {
        switch StoreManager.shared.tier {
        case .basic: return "Upmarket Basic"
        case .pro:   return "Upmarket Pro"
        case .max:   return "Upmarket Max"
        }
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func statusItem(title: String, systemImage: String) -> NSMenuItem {
        let item = disabledItem(title)
        item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        return item
    }

    private func actionItem(
        title: String,
        systemImage: String,
        action: Selector,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        return item
    }

    @objc private func convertDocument(_ sender: Any?) {
        MainWindowController.shared.show(pickFile: true)
    }

    @objc private func showMainWindow(_ sender: Any?) {
        MainWindowController.shared.show()
    }

    @objc private func showShelf(_ sender: Any?) {
        if AppVisibilityPreference.showShelf {
            AppVisibilityPreference.showShelf = false
            ShelfWindowController.shared.hide()
        } else {
            AppVisibilityPreference.showShelf = true
            ShelfWindowController.shared.show(ignoringPreference: true)
        }
    }

    @objc private func showPreferences(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        PreferencesWindowController.shared.show()
    }

    @objc private func showReportProblem(_ sender: Any?) {
        ReportProblemWindowController.shared.show()
    }

    @objc private func showPaywall(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        PaywallWindowController.shared.show()
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }
}

@MainActor
final class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()

    private init() {
        let rootView = PreferencesView()
            .environmentObject(ModelManager.shared)
            .environmentObject(StoreManager.shared)
            .environmentObject(ConversionHistoryStore.shared)
            .environmentObject(WatchedFolderService.shared)
        let prefsSize = AppTheme.WindowSize.preferences
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: prefsSize.width, height: prefsSize.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.minSize = NSSize(width: prefsSize.width, height: 400)
        window.maxSize = NSSize(width: prefsSize.width * 1.5, height: NSScreen.main?.frame.height ?? 1000)
        window.contentView = NSHostingView(rootView: rootView)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        guard let window else { return }
        if !window.isVisible {
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class ReportProblemWindowController: NSWindowController {
    static let shared = ReportProblemWindowController()

    private init() {
        let reportSize = AppTheme.WindowSize.modal
        let rootView = ReportProblemView()
            .environmentObject(ConversionQueue.shared)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: reportSize.width, height: reportSize.height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Report a Problem"
        window.contentView = NSHostingView(rootView: rootView)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        guard let window else { return }
        if !window.isVisible {
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
