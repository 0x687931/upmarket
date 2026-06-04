import AppKit
import SwiftUI

/// Manages the first-launch tour.
/// Shows NSPanel callout bubbles pointing at the actual shelf buttons.
@MainActor
final class TourManager {

    static let shared = TourManager()
    private init() {}

    private(set) var isActive = false
    private(set) var currentStep = 0

    private var calloutPanel: NSPanel?
    private var overlayPanel: NSPanel?  // dim background

    let steps: [TourStep] = [
        TourStep(
            id: 0,
            title: "Welcome to Upmarket",
            body: "Drop or choose a document. Upmarket converts it to clean Markdown on this Mac.",
            symbol: "number.square.fill",
            symbolColor: Color(nsColor: .controlAccentColor),
            action: "Let's go",
            shelfAnchor: .none
        ),
        TourStep(
            id: 1,
            title: "Open the shelf",
            body: "Tap the arrow to open the queue. Files and results appear here.",
            symbol: "arrow.right",
            symbolColor: Color(nsColor: .systemBlue),
            action: "Got it",
            shelfAnchor: .expandButton
        ),
        TourStep(
            id: 2,
            title: "Add files",
            body: "Tap + to choose files, or drag and drop anything onto the shelf.",
            symbol: "plus",
            symbolColor: .green,
            action: "Got it",
            shelfAnchor: .addButton
        ),
        TourStep(
            id: 3,
            title: "Move it anywhere",
            body: "Drag the shelf to any corner of your screen. It snaps into place.",
            symbol: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left",
            symbolColor: Color(nsColor: .controlAccentColor),
            action: "Got it",
            shelfAnchor: .none
        ),
        TourStep(
            id: 4,
            title: "Menu bar",
            body: "Look for Upmarket's # icon at the top right. It shows status and reopens the shelf.",
            symbol: "number.square",
            symbolColor: Color(nsColor: .labelColor),
            action: "Got it",
            shelfAnchor: .menuBar
        ),
        TourStep(
            id: 5,
            title: "Hide when done",
            body: "Tap x to hide the shelf. It stays in your menu bar, ready when you need it.",
            symbol: "xmark",
            symbolColor: .red,
            action: "Finish tour",
            shelfAnchor: .closeButton
        ),
    ]

    // MARK: - Start / Stop

    func startIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "upmarket.tourComplete") else { return }
        start()
    }

    func start() {
        isActive = true
        currentStep = 0
        showStep(0)
    }

    func advance() {
        let next = currentStep + 1
        if next >= steps.count {
            finish()
        } else {
            currentStep = next
            showStep(next)
        }
    }

    func skip() {
        finish()
    }

    private func finish() {
        dismissCallout()
        NotificationCenter.default.post(name: .upmarketSetShelfSpotlight, object: nil)
        isActive = false
        UserDefaults.standard.set(true, forKey: "upmarket.tourComplete")
    }

    // MARK: - Callout display

    private func showStep(_ index: Int) {
        dismissCallout()
        let step = steps[index]
        performStepEffect(step)

        let placement = placement(for: step, size: CGSize(width: 300, height: 188))
        let calloutView = TourCalloutView(step: step, stepIndex: index, total: steps.count, arrowEdge: placement.arrowEdge) {
            TourManager.shared.advance()
        } onSkip: {
            TourManager.shared.skip()
        }

        let hosting = NSHostingView(rootView: calloutView)
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.isOpaque = false
        hosting.layer?.masksToBounds = false

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu   // above everything including shelf
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting

        // Size and position near shelf anchor
        let size = placement.frame.size
        panel.setContentSize(size)
        panel.setFrame(placement.frame, display: false)

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        calloutPanel = panel
    }

    private func performStepEffect(_ step: TourStep) {
        NotificationCenter.default.post(
            name: .upmarketSetShelfSpotlight,
            object: step.shelfAnchor.spotlightID
        )

        switch step.shelfAnchor {
        case .addButton:
            NotificationCenter.default.post(name: .upmarketSetShelfExpanded, object: true)
        case .closeButton:
            NotificationCenter.default.post(name: .upmarketSetShelfExpanded, object: false)
        case .none where step.id == 3:
            ShelfWindowController.shared.animateTourDragDemo()
        default:
            break
        }
    }

    private func dismissCallout() {
        guard let panel = calloutPanel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
        calloutPanel = nil
    }

    // MARK: - Positioning

    private func placement(for step: TourStep, size: CGSize) -> (frame: NSRect, arrowEdge: TourArrowEdge) {
        guard let shelf = ShelfWindowController.shared.window else {
            return (centreFrame(size: size), .none)
        }

        let shelfFrame = shelf.frame
        let screen = shelf.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? shelfFrame.insetBy(dx: -400, dy: -400)
        let gap: CGFloat = 12
        let side = sideFrame(nextTo: shelfFrame, size: size, visible: visible, gap: gap)

        switch step.shelfAnchor {
        case .none:
            return (centreFrame(size: size), .none)

        case .closeButton:
            return (clamp(side.frame, to: visible), side.arrowEdge)

        case .addButton:
            return (clamp(side.frame, to: visible), side.arrowEdge)

        case .expandButton:
            return (clamp(side.frame, to: visible), side.arrowEdge)

        case .menuBar:
            guard let screen = NSScreen.main else { return (centreFrame(size: size), .none) }
            let frame = NSRect(
                x: screen.visibleFrame.maxX - size.width - 16,
                y: screen.frame.maxY - size.height - 36,
                width: size.width, height: size.height
            )
            return (clamp(frame, to: screen.visibleFrame), .top)
        }
    }

    private func sideFrame(nextTo shelfFrame: NSRect, size: CGSize, visible: NSRect, gap: CGFloat) -> (frame: NSRect, arrowEdge: TourArrowEdge) {
        if shelfFrame.maxX + gap + size.width <= visible.maxX {
            return (
                NSRect(x: shelfFrame.maxX + gap, y: shelfFrame.midY - size.height / 2, width: size.width, height: size.height),
                .left
            )
        }
        return (
            NSRect(x: shelfFrame.minX - gap - size.width, y: shelfFrame.midY - size.height / 2, width: size.width, height: size.height),
            .right
        )
    }

    private func clamp(_ frame: NSRect, to visible: NSRect) -> NSRect {
        NSRect(
            x: min(max(frame.minX, visible.minX + 8), visible.maxX - frame.width - 8),
            y: min(max(frame.minY, visible.minY + 8), visible.maxY - frame.height - 8),
            width: frame.width,
            height: frame.height
        )
    }

    private func centreFrame(size: CGSize) -> NSRect {
        guard let screen = NSScreen.main else { return NSRect(origin: .zero, size: size) }
        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2,
            width: size.width, height: size.height
        )
    }
}

enum TourArrowEdge {
    case none, left, right, top
}

// MARK: - Tour Step Model

struct TourStep {
    let id: Int
    let title: String
    let body: String
    let symbol: String
    let symbolColor: Color
    let action: String
    let shelfAnchor: ShelfAnchorPosition

    enum ShelfAnchorPosition {
        case none, closeButton, addButton, expandButton, menuBar

        var spotlightID: String? {
            switch self {
            case .closeButton: return "closeButton"
            case .addButton: return "addButton"
            case .expandButton: return "expandButton"
            case .none, .menuBar: return nil
            }
        }
    }
}

// MARK: - Callout View

struct TourCalloutView: View {
    let step: TourStep
    let stepIndex: Int
    let total: Int
    let arrowEdge: TourArrowEdge
    let onAdvance: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 10) {
                // Step indicator + skip
                HStack {
                    ZStack(alignment: .leading) {
                        TourWindowDragHandle()
                            .frame(width: 132, height: 24)
                        Label("Upmarket", systemImage: "number.square.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .allowsHitTesting(false)
                    }
                    .help("Drag tour")
                    Spacer()
                    // Dots
                    HStack(spacing: 4) {
                        ForEach(0..<total, id: \.self) { i in
                            Circle()
                                .fill(i == stepIndex ? Color.accentColor : Color.primary.opacity(0.2))
                                .frame(width: i == stepIndex ? 7 : 5, height: i == stepIndex ? 7 : 5)
                                .animation(.spring(duration: 0.3), value: stepIndex)
                        }
                    }
                    Button("Skip") { onSkip() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Symbol + title
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(step.symbolColor.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: step.symbol)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(step.symbolColor)
                            .symbolRenderingMode(.hierarchical)
                    }
                    Text(step.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                }

                // Body
                Text(step.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Action button
                Button(action: onAdvance) {
                    Text(step.action)
                        .font(.subheadline).fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(16)

            pointer
        }
        .frame(width: 300, height: 188)
    }

    @ViewBuilder private var pointer: some View {
        switch arrowEdge {
        case .none:
            EmptyView()
        case .left:
            Triangle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: 14, height: 20)
                .rotationEffect(.degrees(-90))
                .offset(x: -157)
        case .right:
            Triangle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: 14, height: 20)
                .rotationEffect(.degrees(90))
                .offset(x: 157)
        case .top:
            Triangle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: 18, height: 14)
                .offset(y: -100)
        }
    }
}

private struct TourWindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleView {
        DragHandleView()
    }

    func updateNSView(_ nsView: DragHandleView, context: Context) {}

    final class DragHandleView: NSView {
        private var initialMouseLocation: NSPoint = .zero
        private var initialWindowOrigin: NSPoint = .zero
        private var pushedCursor = false

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            initialMouseLocation = NSEvent.mouseLocation
            initialWindowOrigin = window.frame.origin
            NSCursor.closedHand.push()
            pushedCursor = true
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window else { return }
            let current = NSEvent.mouseLocation
            window.setFrameOrigin(NSPoint(
                x: initialWindowOrigin.x + current.x - initialMouseLocation.x,
                y: initialWindowOrigin.y + current.y - initialMouseLocation.y
            ))
        }

        override func mouseUp(with event: NSEvent) {
            if pushedCursor {
                NSCursor.pop()
                pushedCursor = false
            }
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
