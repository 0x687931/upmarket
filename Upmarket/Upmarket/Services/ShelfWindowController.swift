import AppKit
import SwiftUI

/// Manages the conversion queue shelf window.
/// Sits to the left of the Dock, flush with the screen bottom — exactly like Dockside.
final class ShelfWindowController: NSWindowController {

    static let shared = ShelfWindowController()

    private let positioner = ShelfPositioner.shared
    private var mouseMonitor: Any?
    private var workspaceObserver: NSObjectProtocol?
    private let restingShelfSize = ShelfLayout.miniSize
    private let shelfInset: CGFloat = 10
    private let snapRadius: CGFloat = 60

    // Persisted shelf position preference
    enum ShelfAnchor: Int {
        case bottomLeft = 0
        case bottomRight = 1
        case topLeft = 2
        case topRight = 3
        case center = 4
    }

    var anchor: ShelfAnchor {
        get {
            guard UserDefaults.standard.object(forKey: "upmarket.shelfAnchor") != nil else { return .center }
            return ShelfAnchor(rawValue: UserDefaults.standard.integer(forKey: "upmarket.shelfAnchor")) ?? .center
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "upmarket.shelfAnchor") }
    }

    // MARK: - Init

    private init() {
        let panel = Self.makePanel()
        super.init(window: panel)
        configureContent()
        startMonitoring()
        reposition()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Panel

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level                   = .floating
        panel.collectionBehavior      = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate       = false
        panel.isOpaque                = false
        panel.backgroundColor         = .clear
        panel.hasShadow               = true
        panel.animationBehavior       = .utilityWindow
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility         = .hidden
        return panel
    }

    // MARK: - Content

    private func configureContent() {
        guard let panel = window else { return }
        panel.delegate = self

        let hosting = NSHostingView(rootView:
            ShelfView()
                .environmentObject(ConversionQueue.shared)
                .environmentObject(StoreManager.shared)
                .environmentObject(ModelManager.shared)
        )
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting
    }

    // MARK: - Positioning
    // Matches Dockside: shelf sits to the left of the Dock, flush with screen bottom.

    func reposition() {
        guard let panel = window else { return }
        let frame = shelfFrame()
        panel.setFrame(frame, display: true)
    }

    private func shelfFrame() -> NSRect {
        let screen = positioner.primaryScreen
        let visible = screen.visibleFrame
        let w = restingShelfSize.width
        let h = restingShelfSize.height

        switch anchor {
        case .center:
            return NSRect(x: visible.midX - w / 2, y: visible.midY - h / 2, width: w, height: h)
        case .bottomLeft:
            return NSRect(x: visible.minX + shelfInset, y: visible.minY + shelfInset, width: w, height: h)
        case .bottomRight:
            return NSRect(x: visible.maxX - w - shelfInset, y: visible.minY + shelfInset, width: w, height: h)
        case .topLeft:
            return NSRect(x: visible.minX + shelfInset, y: visible.maxY - h - shelfInset, width: w, height: h)
        case .topRight:
            return NSRect(x: visible.maxX - w - shelfInset, y: visible.maxY - h - shelfInset, width: w, height: h)
        }
    }

    /// Call this when the user finishes dragging the shelf window.
    /// Snaps to the nearest screen corner/edge.
    func snapToNearestCorner() {
        guard let panel = window else { return }
        let mid = NSPoint(
            x: panel.frame.midX,
            y: panel.frame.midY
        )
        let screen = positioner.primaryScreen
        let visible = screen.visibleFrame

        // Determine which corner is closest
        let corners: [(ShelfAnchor, NSPoint)] = [
            (.bottomLeft,  NSPoint(x: visible.minX, y: visible.minY)),
            (.bottomRight, NSPoint(x: visible.maxX, y: visible.minY)),
            (.topLeft,     NSPoint(x: visible.minX, y: visible.maxY)),
            (.topRight,    NSPoint(x: visible.maxX, y: visible.maxY)),
        ]

        let nearest = corners.min {
            distance($0.1, mid) < distance($1.1, mid)
        }

        if let nearest {
            anchor = nearest.0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(shelfFrame(), display: true)
            }
        }
    }

    private func distance(_ a: NSPoint, _ b: NSPoint) -> CGFloat {
        sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2))
    }

    // MARK: - Show / Hide

    func show(animate: Bool = true, ignoringPreference: Bool = false) {
        guard let panel = window else { return }
        guard ignoringPreference || AppVisibilityPreference.showShelf else { return }
        reposition()
        if animate {
            panel.alphaValue = 0
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
            panel.orderFront(nil)
        }
    }

    func centerForFirstLaunchTour() {
        guard !UserDefaults.standard.bool(forKey: "upmarket.tourComplete") else { return }
        anchor = .center
        reposition()
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
        if panel.isVisible {
            hide()
        } else {
            AppVisibilityPreference.showShelf = true
            show(ignoringPreference: true)
        }
    }

    func resizeToContent(width: CGFloat) {
        resizeToContent(width: width, height: window?.frame.height ?? ShelfLayout.closedHeight)
    }

    func resizeToContent(width: CGFloat, height: CGFloat) {
        guard let panel = window else { return }
        var frame = panel.frame
        let oldSize = frame.size
        frame.size.width = width
        frame.size.height = height

        switch anchor {
        case .bottomLeft:
            break
        case .bottomRight:
            frame.origin.x += oldSize.width - width
        case .topLeft:
            frame.origin.y += oldSize.height - height
        case .topRight:
            frame.origin.x += oldSize.width - width
            frame.origin.y += oldSize.height - height
        case .center:
            frame.origin.x += (oldSize.width - width) / 2
            frame.origin.y += (oldSize.height - height) / 2
        }

        panel.setFrame(frame, display: false)
    }

    func animateTourDragDemo() {
        guard let panel = window else { return }
        let originalAnchor = anchor
        let demoAnchors: [ShelfAnchor] = [.bottomLeft, .topLeft, .topRight, .bottomRight, originalAnchor]

        for (index, demoAnchor) in demoAnchors.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.9) { [weak self] in
                guard let self else { return }
                self.anchor = demoAnchor
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.65
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    panel.animator().setFrame(self.shelfFrame(), display: true)
                }
            }
        }
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        // Reposition on screen changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Auto-hide with Dock if enabled
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            guard let self, self.positioner.isDockAutoHiding else { return }
            let loc = NSEvent.mouseLocation
            if self.positioner.shouldBeVisible(mouseLocation: loc) {
                if !(self.window?.isVisible ?? false) { self.show() }
            }
        }
    }

    @objc private func screenChanged() {
        reposition()
    }
}

// MARK: - NSWindowDelegate — snap on drag end

extension ShelfWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        // Snap to nearest corner after user stops dragging
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        perform(#selector(delayedSnap), with: nil, afterDelay: 0.3)
    }

    @objc private func delayedSnap() {
        snapToNearestCorner()
    }
}
