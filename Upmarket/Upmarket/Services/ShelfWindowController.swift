import AppKit
import SwiftUI

/// Manages the conversion queue shelf window.
/// Sits to the left of the Dock, flush with the screen bottom — exactly like Dockside.
final class ShelfWindowController: NSWindowController {

    static let shared = ShelfWindowController()

    private let positioner = ShelfPositioner.shared
    private var mouseMonitor: Any?
    private var workspaceObserver: NSObjectProtocol?
    private let shelfSize:  CGFloat = 97   // closed: colWidth*2+1 = 97pt wide, 108pt tall
    private let shelfInset: CGFloat = 10
    private let snapRadius: CGFloat = 60

    // Persisted shelf position preference
    enum ShelfAnchor: Int {
        case bottomLeft = 0
        case bottomRight = 1
        case topLeft = 2
        case topRight = 3
    }

    var anchor: ShelfAnchor {
        get { ShelfAnchor(rawValue: UserDefaults.standard.integer(forKey: "upmarket.shelfAnchor")) ?? .bottomLeft }
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
        // Start as a square — ShelfView will call resizeToContent when it expands
        let w = shelfSize       // 97pt wide (48×2 + 1 divider)
        let h: CGFloat = 108   // 108pt tall (3 × 36pt buttons)

        switch anchor {
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

    func show(animate: Bool = true) {
        guard let panel = window else { return }
        reposition()
        if animate {
            panel.alphaValue = 0
            panel.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
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
        panel.isVisible ? hide() : show()
    }

    /// Called when user drags the resize handle — updates window width.
    func resizeToContent(width: CGFloat) {
        guard let panel = window else { return }
        var frame = panel.frame
        frame.size.width = width
        panel.setFrame(frame, display: true)
    }

    func animateTourDragDemo() {
        guard let panel = window else { return }
        let originalAnchor = anchor
        let demoAnchors: [ShelfAnchor] = [.bottomLeft, .topLeft, .topRight, .bottomRight, originalAnchor]

        for (index, demoAnchor) in demoAnchors.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.45) { [weak self] in
                guard let self else { return }
                self.anchor = demoAnchor
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.35
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
