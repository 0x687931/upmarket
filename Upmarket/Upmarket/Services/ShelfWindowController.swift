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
    private let shelfInset: CGFloat = 0
    private let snapRadius: CGFloat = 60
    // Suppresses the drag-snap logic when we programmatically resize the panel.
    private var isProgrammaticResize = false

    // Persisted shelf position preference
    enum ShelfAnchor: Int {
        case bottomLeft = 0
        case bottomRight = 1
        case topLeft = 2
        case topRight = 3
        case center = 4
    }

    enum ShelfExpansionAxis {
        case up, down, left, right
    }

    var anchor: ShelfAnchor {
        get {
            guard UserDefaults.standard.object(forKey: "upmarket.shelfAnchor") != nil else { return .bottomRight }
            return ShelfAnchor(rawValue: UserDefaults.standard.integer(forKey: "upmarket.shelfAnchor")) ?? .bottomRight
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
        // The AppKit window shadow is generated from the content view's backing-layer mask,
        // not from the SwiftUI clipShape. Without rounding the layer here, the shadow stays
        // rectangular and its square corners poke out behind the rounded SwiftUI clip — the
        // recurring "square corners" bug. Match the SwiftUI panel radius so the shadow rounds too.
        hosting.layer?.cornerRadius = ShelfLayout.panelCornerRadius
        hosting.layer?.cornerCurve = .continuous
        hosting.layer?.masksToBounds = true
        // Disable automatic window resizing — we size the panel ourselves via resizeToContent.
        // Without this, NSHostingView grows the panel from its top-left corner (down+right),
        // which is the opposite of what corner-anchored expansion requires.
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = []
        }
        panel.contentView = hosting
    }

    // MARK: - Positioning
    // Matches Dockside: shelf sits to the left of the Dock, flush with screen bottom.

    func reposition() {
        guard let panel = window else { return }
        panel.setFrame(shelfFrame(), display: true)
    }

    private func shelfFrame() -> NSRect {
        let screen = positioner.primaryScreen
        let visible = screen.visibleFrame
        let w = restingShelfSize.width
        let h = restingShelfSize.height
        let origin = anchoredOrigin(size: CGSize(width: w, height: h), in: visible)
        return NSRect(origin: origin, size: CGSize(width: w, height: h))
    }

    func anchoredOrigin(size: CGSize, in visible: NSRect) -> NSPoint {
        switch anchor {
        case .center:
            return NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        case .bottomLeft:
            return NSPoint(x: visible.minX + shelfInset, y: visible.minY + shelfInset)
        case .bottomRight:
            return NSPoint(x: visible.maxX - size.width - shelfInset, y: visible.minY + shelfInset)
        case .topLeft:
            return NSPoint(x: visible.minX + shelfInset, y: visible.maxY - size.height - shelfInset)
        case .topRight:
            return NSPoint(x: visible.maxX - size.width - shelfInset, y: visible.maxY - size.height - shelfInset)
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
            NotificationCenter.default.post(name: .upmarketShelfAnchorChanged, object: nearest.0.rawValue)
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
        resizeToContent(width: width, height: window?.frame.height ?? ShelfLayout.miniSize.height)
    }

    func resizeToContent(width: CGFloat, height: CGFloat) {
        guard let panel = window else { return }
        let newSize = CGSize(width: width, height: height)
        let visible = positioner.primaryScreen.visibleFrame
        let origin = anchoredOrigin(size: newSize, in: visible)
        let newFrame = NSRect(origin: origin, size: newSize)
        guard newFrame != panel.frame else { return }
        isProgrammaticResize = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(newFrame, display: true)
        }, completionHandler: { [weak self] in
            self?.isProgrammaticResize = false
        })
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

extension ShelfWindowController.ShelfAnchor {
    var verticalExpansion: ShelfWindowController.ShelfExpansionAxis {
        switch self {
        case .bottomLeft, .bottomRight, .center:
            return .up
        case .topLeft, .topRight:
            return .down
        }
    }

    var horizontalExpansion: ShelfWindowController.ShelfExpansionAxis {
        switch self {
        case .bottomLeft, .topLeft, .center:
            return .right
        case .bottomRight, .topRight:
            return .left
        }
    }
}

extension ShelfWindowController {
    static func resizedFrame(_ frame: NSRect, to newSize: CGSize, anchor: ShelfAnchor) -> NSRect {
        var result = frame
        let oldSize = frame.size
        let widthDelta = oldSize.width - newSize.width
        let heightDelta = oldSize.height - newSize.height

        switch anchor.horizontalExpansion {
        case .left:
            result.origin.x += widthDelta
        case .right:
            break
        case .up, .down:
            break
        }

        switch anchor.verticalExpansion {
        case .down:
            result.origin.y += heightDelta
        case .up:
            break
        case .left, .right:
            break
        }

        if anchor == .center {
            result.origin.x += widthDelta / 2
            result.origin.y += heightDelta / 2
        }

        result.size = newSize
        return result
    }
}

// MARK: - NSWindowDelegate — snap on drag end

extension ShelfWindowController: NSWindowDelegate {
    func windowDidMove(_ notification: Notification) {
        // Ignore moves we triggered programmatically (hover expand/collapse).
        guard !isProgrammaticResize else { return }
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        perform(#selector(delayedSnap), with: nil, afterDelay: 0.3)
    }

    @objc private func delayedSnap() {
        // Only snap when at resting (mini) size — expanded state means the user
        // is hovering, not dragging, so snapping would collapse the shelf.
        guard let panel = window, panel.frame.size == restingShelfSize else { return }
        snapToNearestCorner()
    }
}
