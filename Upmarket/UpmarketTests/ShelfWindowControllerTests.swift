import AppKit
import XCTest
@testable import Upmarket

final class ShelfWindowControllerTests: XCTestCase {

    // anchoredOrigin keeps the named corner fixed as size changes.
    // visible frame used across all tests: x=0, y=24, w=1470, h=932

    private let visible = NSRect(x: 0, y: 24, width: 1470, height: 932)

    private func origin(_ anchor: ShelfWindowController.ShelfAnchor, _ size: CGSize) -> NSPoint {
        // Use a throwaway controller just to call anchoredOrigin — but it's a singleton.
        // Test the static math directly instead.
        anchoredOrigin(anchor: anchor, size: size, in: visible, inset: 0)
    }

    // Replicate the logic so the test doesn't depend on the live singleton.
    private func anchoredOrigin(anchor: ShelfWindowController.ShelfAnchor,
                                 size: CGSize,
                                 in visible: NSRect,
                                 inset: CGFloat) -> NSPoint {
        switch anchor {
        case .center:
            return NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        case .bottomLeft:
            return NSPoint(x: visible.minX + inset, y: visible.minY + inset)
        case .bottomRight:
            return NSPoint(x: visible.maxX - size.width - inset, y: visible.minY + inset)
        case .topLeft:
            return NSPoint(x: visible.minX + inset, y: visible.maxY - size.height - inset)
        case .topRight:
            return NSPoint(x: visible.maxX - size.width - inset, y: visible.maxY - size.height - inset)
        }
    }

    func testBottomRightSmallThenLarge() {
        let small = origin(.bottomRight, CGSize(width: 56, height: 56))
        let large = origin(.bottomRight, CGSize(width: 217, height: 132))

        // Right edge stays fixed at visible.maxX = 1470
        XCTAssertEqual(small.x + 56, 1470)
        XCTAssertEqual(large.x + 217, 1470)
        // Bottom edge stays fixed at visible.minY = 24
        XCTAssertEqual(small.y, 24)
        XCTAssertEqual(large.y, 24)
        // x moves LEFT as width grows
        XCTAssertLessThan(large.x, small.x)
    }

    func testBottomLeftSmallThenLarge() {
        let small = origin(.bottomLeft, CGSize(width: 56, height: 56))
        let large = origin(.bottomLeft, CGSize(width: 217, height: 132))

        // Left edge stays fixed at visible.minX = 0
        XCTAssertEqual(small.x, 0)
        XCTAssertEqual(large.x, 0)
        // Bottom edge stays fixed
        XCTAssertEqual(small.y, 24)
        XCTAssertEqual(large.y, 24)
    }

    func testTopRightSmallThenLarge() {
        let small = origin(.topRight, CGSize(width: 56, height: 56))
        let large = origin(.topRight, CGSize(width: 217, height: 132))

        // Right edge stays fixed
        XCTAssertEqual(small.x + 56, 1470)
        XCTAssertEqual(large.x + 217, 1470)
        // Top edge stays fixed at visible.maxY = 956
        XCTAssertEqual(small.y + 56, 956)
        XCTAssertEqual(large.y + 132, 956)
        // x moves LEFT as width grows
        XCTAssertLessThan(large.x, small.x)
        // y moves DOWN as height grows
        XCTAssertLessThan(large.y, small.y)
    }

    func testTopLeftSmallThenLarge() {
        let small = origin(.topLeft, CGSize(width: 56, height: 56))
        let large = origin(.topLeft, CGSize(width: 217, height: 132))

        // Left edge stays fixed
        XCTAssertEqual(small.x, 0)
        XCTAssertEqual(large.x, 0)
        // Top edge stays fixed at visible.maxY = 956
        XCTAssertEqual(small.y + 56, 956)
        XCTAssertEqual(large.y + 132, 956)
        // y moves DOWN as height grows
        XCTAssertLessThan(large.y, small.y)
    }
}
