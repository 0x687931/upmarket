import AppKit
import Combine
import SwiftUI

private let appGroupID = "group.com.upmarket.app"

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
        AppVisibilityPreference.apply()
        if AppRuntime.isRunningUITests {
            MainWindowController.shared.show()
        }

        NSApp.servicesProvider = self
        MemoryPressureMonitor.shared.start()
        removeStaleQuickActionHandoffs()

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
        menu.addItem(dockMenuItem(title: shelfDockTitle, action: #selector(dockShowShelf(_:))))

        menu.addItem(.separator())

        menu.addItem(dockMenuItem(title: historyDockTitle, action: #selector(dockShowHistory(_:))))
        menu.addItem(dockMenuItem(title: "Preferences…", action: #selector(dockShowPreferences(_:))))

        return menu
    }

    private var shelfDockTitle: String {
        let count = ConversionQueue.shared.jobs.count
        return count > 0 ? "Show Shelf (\(count))" : "Show Shelf"
    }

    private var historyDockTitle: String {
        let count = ConversionHistoryStore.shared.records.count
        return count > 0 ? "History (\(count))" : "History"
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

    @objc private func dockShowHistory(_ sender: Any?) {
        HistoryWindowController.shared.show()
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
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
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

    private func removeStaleQuickActionHandoffs() {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
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
    private static let size = NSSize(width: 22, height: 22)

    static func image(isConverting: Bool) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let iconRect = NSRect(x: 1.5, y: 1.5, width: 19, height: 19)
        let iconPath = NSBezierPath(roundedRect: iconRect, xRadius: 4.75, yRadius: 4.75)
        let gradient = NSGradient(colors: gradientColors(isConverting: isConverting))
        gradient?.draw(in: iconPath, angle: -90)

        NSColor.white.withAlphaComponent(0.12).setFill()
        NSBezierPath(ovalIn: NSRect(x: 5, y: 15.5, width: 12, height: 3)).fill()

        if let symbol = symbolImage(name: UpmarketSymbols.menuBarIcon(isConverting: isConverting)) {
            symbol.draw(
                in: NSRect(x: 4.25, y: 3.25, width: 13.5, height: 13.5),
                from: NSRect(origin: .zero, size: symbol.size),
                operation: .sourceOver,
                fraction: 1
            )
        }

        if isConverting {
            NSColor.controlAccentColor.setFill()
            let activityDot = NSBezierPath(ovalIn: NSRect(x: 15.5, y: 1.5, width: 5, height: 5))
            activityDot.fill()
            NSColor.white.withAlphaComponent(0.92).setStroke()
            activityDot.lineWidth = 0.8
            activityDot.stroke()
        }

        image.isTemplate = false
        return image
    }

    private static func gradientColors(isConverting: Bool) -> [NSColor] {
        if isConverting {
            return [
                NSColor(calibratedRed: 1.00, green: 0.77, blue: 0.24, alpha: 1),
                NSColor(calibratedRed: 0.97, green: 0.42, blue: 0.00, alpha: 1),
                NSColor(calibratedRed: 0.73, green: 0.17, blue: 0.00, alpha: 1)
            ]
        }
        return [
            NSColor(calibratedRed: 1.00, green: 0.75, blue: 0.25, alpha: 1),
            NSColor(calibratedRed: 0.91, green: 0.47, blue: 0.00, alpha: 1),
            NSColor(calibratedRed: 0.66, green: 0.22, blue: 0.00, alpha: 1)
        ]
    }

    private static func symbolImage(name: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: "Upmarket")?
            .withSymbolConfiguration(configuration)
        else {
            return nil
        }

        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        let rect = NSRect(origin: .zero, size: symbol.size)
        symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSColor.white.setFill()
        rect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        tinted.isTemplate = false
        return tinted
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
            let title = percent > 0 ? "Converting \(percent)%" : "Converting..."
            menu.addItem(disabledItem(title))
            menu.addItem(.separator())
        }

        menu.addItem(actionItem(
            title: "Convert Document...",
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
            title: shelfTitle,
            systemImage: "sidebar.right",
            action: #selector(showShelf(_:)),
            keyEquivalent: "s",
            modifiers: [.command, .shift]
        ))
        menu.addItem(actionItem(
            title: historyTitle,
            systemImage: "clock",
            action: #selector(showHistory(_:))
        ))

        menu.addItem(.separator())

        menu.addItem(actionItem(
            title: "Preferences...",
            systemImage: "gearshape",
            action: #selector(showPreferences(_:)),
            keyEquivalent: ",",
            modifiers: [.command]
        ))
        menu.addItem(actionItem(
            title: "Report a Problem...",
            systemImage: "exclamationmark.bubble",
            action: #selector(showReportProblem(_:))
        ))

        menu.addItem(.separator())
        menu.addItem(disabledItem(entitlementTitle))
        menu.addItem(.separator())

        menu.addItem(actionItem(
            title: "Quit Upmarket",
            systemImage: "power",
            action: #selector(quit(_:)),
            keyEquivalent: "q",
            modifiers: [.command]
        ))
    }

    private var shelfTitle: String {
        let count = ConversionQueue.shared.jobs.count
        return count > 0 ? "Show Shelf (\(count))" : "Show Shelf"
    }

    private var historyTitle: String {
        let count = ConversionHistoryStore.shared.records.count
        return count > 0 ? "History (\(count))" : "History"
    }

    private var entitlementTitle: String {
        switch StoreManager.shared.entitlement {
        case .none:
            return "Locked"
        case .basic:
            return "Upmarket"
        case .pro:
            return "Upmarket + AI"
        }
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
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
        AppVisibilityPreference.showShelf = true
        ShelfWindowController.shared.show(ignoringPreference: true)
    }

    @objc private func showHistory(_ sender: Any?) {
        HistoryWindowController.shared.show()
    }

    @objc private func showPreferences(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        PreferencesWindowController.shared.show()
    }

    @objc private func showReportProblem(_ sender: Any?) {
        ReportProblemWindowController.shared.show()
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
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
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
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class HistoryWindowController: NSWindowController {
    static let shared = HistoryWindowController()

    private init() {
        let rootView = HistoryPopover(historyStore: ConversionHistoryStore.shared)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 380),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "History"
        window.contentView = NSHostingView(rootView: rootView)
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        ConversionHistoryStore.shared.load()
        guard let window else { return }
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class ReportProblemWindowController: NSWindowController {
    static let shared = ReportProblemWindowController()

    private init() {
        let rootView = ReportProblemView()
            .environmentObject(ConversionQueue.shared)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
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
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
