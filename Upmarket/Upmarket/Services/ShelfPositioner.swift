import AppKit

/// Detects the Dock position and calculates where to place the Upmarket shelf.
/// Mirrors Dockside's approach: shelf lives adjacent to the Dock, follows it.
final class ShelfPositioner {

    static let shared = ShelfPositioner()
    private init() {}

    enum DockEdge {
        case bottom, left, right
    }

    // MARK: - Dock detection

    var dockEdge: DockEdge {
        // Read Dock orientation from defaults — same approach as Dockside
        let orientation = UserDefaults(suiteName: "com.apple.dock")?
            .string(forKey: "orientation") ?? "bottom"
        switch orientation {
        case "left":  return .left
        case "right": return .right
        default:      return .bottom
        }
    }

    var isDockAutoHiding: Bool {
        UserDefaults(suiteName: "com.apple.dock")?
            .bool(forKey: "autohide") ?? false
    }

    var primaryScreen: NSScreen {
        // Dock lives on the primary screen (the one with the menu bar)
        NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: - Shelf frame calculation

    /// Calculate the frame for the shelf window adjacent to the Dock.
    func shelfFrame(shelfSize: NSSize) -> NSRect {
        let screen = primaryScreen
        let visibleFrame = screen.visibleFrame   // excludes menu bar and Dock
        let fullFrame    = screen.frame

        switch dockEdge {
        case .bottom:
            // Shelf sits just above the Dock, on the right side of the screen
            let dockHeight = fullFrame.height - visibleFrame.height - visibleFrame.origin.y
            let x = fullFrame.maxX - shelfSize.width - 8
            let y = dockHeight + 4
            return NSRect(x: x, y: y, width: shelfSize.width, height: shelfSize.height)

        case .left:
            // Dock on left → shelf sits to the right of the Dock
            let dockWidth = visibleFrame.origin.x
            let x = dockWidth + 4
            let y = fullFrame.midY - shelfSize.height / 2
            return NSRect(x: x, y: y, width: shelfSize.width, height: shelfSize.height)

        case .right:
            // Dock on right → shelf sits to the left of the Dock
            let dockWidth = fullFrame.width - visibleFrame.maxX
            let x = visibleFrame.maxX - shelfSize.width - dockWidth - 4
            let y = fullFrame.midY - shelfSize.height / 2
            return NSRect(x: x, y: y, width: shelfSize.width, height: shelfSize.height)
        }
    }

    /// Whether the shelf should be visible given current state.
    func shouldBeVisible(mouseLocation: NSPoint? = nil) -> Bool {
        guard isDockAutoHiding else { return true }
        guard let mouse = mouseLocation else { return false }

        // Show when mouse is near the Dock edge (same as Dockside)
        let screen = primaryScreen
        let threshold: CGFloat = 80

        switch dockEdge {
        case .bottom: return mouse.y < threshold
        case .left:   return mouse.x < threshold
        case .right:  return mouse.x > screen.frame.maxX - threshold
        }
    }
}
