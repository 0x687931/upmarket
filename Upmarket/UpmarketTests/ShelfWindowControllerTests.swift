import AppKit
import XCTest
@testable import Upmarket

final class ShelfWindowControllerTests: XCTestCase {
    func testResizedFramePinsBottomLeftCorner() {
        let frame = NSRect(x: 12, y: 18, width: 56, height: 56)

        let resized = ShelfWindowController.resizedFrame(
            frame,
            to: CGSize(width: 216, height: 132),
            anchor: .bottomLeft
        )

        XCTAssertEqual(resized.origin.x, 12)
        XCTAssertEqual(resized.origin.y, 18)
        XCTAssertEqual(resized.size.width, 216)
        XCTAssertEqual(resized.size.height, 132)
    }

    func testResizedFramePinsBottomRightCorner() {
        let frame = NSRect(x: 12, y: 18, width: 56, height: 56)

        let resized = ShelfWindowController.resizedFrame(
            frame,
            to: CGSize(width: 216, height: 132),
            anchor: .bottomRight
        )

        XCTAssertEqual(resized.origin.x, -148)
        XCTAssertEqual(resized.origin.y, 18)
        XCTAssertEqual(resized.size.width, 216)
        XCTAssertEqual(resized.size.height, 132)
    }

    func testResizedFramePinsTopLeftCorner() {
        let frame = NSRect(x: 12, y: 18, width: 56, height: 56)

        let resized = ShelfWindowController.resizedFrame(
            frame,
            to: CGSize(width: 216, height: 132),
            anchor: .topLeft
        )

        XCTAssertEqual(resized.origin.x, 12)
        XCTAssertEqual(resized.origin.y, -58)
        XCTAssertEqual(resized.size.width, 216)
        XCTAssertEqual(resized.size.height, 132)
    }

    func testResizedFramePinsTopRightCorner() {
        let frame = NSRect(x: 12, y: 18, width: 56, height: 56)

        let resized = ShelfWindowController.resizedFrame(
            frame,
            to: CGSize(width: 216, height: 132),
            anchor: .topRight
        )

        XCTAssertEqual(resized.origin.x, -148)
        XCTAssertEqual(resized.origin.y, -58)
        XCTAssertEqual(resized.size.width, 216)
        XCTAssertEqual(resized.size.height, 132)
    }
}
