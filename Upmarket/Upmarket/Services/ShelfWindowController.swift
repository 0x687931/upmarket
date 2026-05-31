import AppKit
import SwiftUI

/// Manages the floating Dock-adjacent shelf window.
/// NSPanel approach mirrors Dockside — floats above all windows,
/// follows Dock position, respects auto-hide, works in fullscreen.
final class ShelfWindowController: NSWindowController {

    static let shared = ShelfWindowController()

    private let positioner = ShelfPositioner.shared
    private var mouseMonitor: Any?
    private var dockObserver: NSKeyValueObservation?

    // MARK: - Init

    private init() {
        let panel = Self.makePanel()
        super.init(window: panel)
        configureContent()
        startMonitoring()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Panel creation

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level                   = .floating
        panel.collectionBehavior      = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate       = false
        panel.isOpaque                = false
        panel.backgroundColor         = .clear
        panel.hasShadow               = true
        panel.animationBehavior       = .utilityWindow
        return panel
    }

    // MARK: - Content

    private func configureContent() {
        guard let panel = window else { return }

        // Liquid glass background via NSVisualEffectView
        let effect = NSVisualEffectView()
        effect.material       = .sidebar
        effect.blendingMode   = .behindWindow
        effect.state          = .active
        effect.wantsLayer     = true
        effect.layer?.cornerRadius = 16
        effect.layer?.masksToBounds = true

        // Host SwiftUI shelf content
        let hosting = NSHostingView(rootView: ShelfView()
            .environmentObject(ConversionService.shared)
            .environmentObject(StoreManager.shared)
            .environmentObject(ModelManager.shared)
        )
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)

        panel.contentView = effect

        // Position adjacent to Dock
        reposition()
    }

    // MARK: - Positioning

    func reposition() {
        guard let panel = window else { return }
        let shelfSize = NSSize(width: 280, height: 480)
        let frame = positioner.shelfFrame(shelfSize: shelfSize)
        panel.setFrame(frame, display: false)
    }

    // MARK: - Show / Hide

    func show(animate: Bool = true) {
        guard let panel = window else { return }
        reposition()
        if animate {
            panel.alphaValue = 0
            panel.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func hide(animate: Bool = true) {
        guard let panel = window else { return }
        if animate {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
                panel.alphaValue = 1
            })
        } else {
            panel.orderOut(nil)
        }
    }

    func toggle() {
        guard let panel = window else { return }
        if panel.isVisible { hide() } else { show() }
    }

    // MARK: - Auto-hide monitoring

    private func startMonitoring() {
        // Watch mouse position for auto-hide Dock behaviour
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self, self.positioner.isDockAutoHiding else { return }
            let loc = NSEvent.mouseLocation
            if self.positioner.shouldBeVisible(mouseLocation: loc) {
                if !(self.window?.isVisible ?? false) { self.show() }
            }
        }

        // Reposition when screen configuration changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Watch for Dock orientation changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenChanged),
            name: NSNotification.Name("com.apple.dock.appledockupdaterequest"),
            object: nil
        )
    }

    @objc private func screenChanged() {
        reposition()
    }
}
