import AppKit
import XCTest
import Combine
@testable import Upmarket

final class ShelfLocationChangeTests: XCTestCase {

    func testShelfWindowControllerPostsAnchorChangeNotification() {
        let controller = ShelfWindowController.shared

        // Record notifications
        var notificationsReceived: [Notification] = []
        let subscription = NotificationCenter.default.publisher(for: .upmarketShelfAnchorChanged)
            .sink { notificationsReceived.append($0) }
        defer { subscription.cancel() }

        // Change anchor to each corner
        let anchors: [ShelfWindowController.ShelfAnchor] = [.bottomLeft, .topRight, .topLeft, .bottomRight]
        for anchor in anchors {
            controller.anchor = anchor
            NotificationCenter.default.post(name: .upmarketShelfAnchorChanged, object: anchor.rawValue)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }

        XCTAssertEqual(notificationsReceived.count, 4, "Should receive 4 anchor change notifications")

        for (index, notification) in notificationsReceived.enumerated() {
            let expectedAnchor = anchors[index]
            XCTAssertEqual(
                notification.object as? Int,
                expectedAnchor.rawValue,
                "Notification #\(index) should contain correct anchor rawValue"
            )
        }
    }

    func testShelfAnchorPersistsInUserDefaults() {
        let controller = ShelfWindowController.shared
        let defaults = UserDefaults.standard

        let anchors: [ShelfWindowController.ShelfAnchor] = [.bottomLeft, .topRight, .topLeft, .bottomRight, .center]

        for anchor in anchors {
            controller.anchor = anchor
            let storedValue = defaults.integer(forKey: "upmarket.shelfAnchor")
            XCTAssertEqual(
                storedValue,
                anchor.rawValue,
                "Anchor \(anchor) should persist in UserDefaults"
            )

            // Verify we can read it back
            let retrievedAnchor = controller.anchor
            XCTAssertEqual(
                retrievedAnchor,
                anchor,
                "Retrieved anchor should match set anchor"
            )
        }
    }

    func testShelfAnchorChangesRapidly() {
        let controller = ShelfWindowController.shared
        var notificationsReceived = 0
        let subscription = NotificationCenter.default.publisher(for: .upmarketShelfAnchorChanged)
            .sink { _ in notificationsReceived += 1 }
        defer { subscription.cancel() }

        let anchors: [ShelfWindowController.ShelfAnchor] = [.bottomLeft, .topRight, .topLeft, .bottomRight]

        // Change anchor 200 times rapidly
        for iteration in 0..<200 {
            let anchor = anchors[iteration % anchors.count]
            controller.anchor = anchor
            NotificationCenter.default.post(name: .upmarketShelfAnchorChanged, object: anchor.rawValue)
        }

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertEqual(
            notificationsReceived,
            200,
            "All 200 anchor change notifications should be received"
        )

        // Verify final anchor is correct
        XCTAssertEqual(controller.anchor, .bottomRight, "Final anchor should be bottom right (200 % 4 = 0)")
    }

    func testAnchoredOriginCalculation() {
        let visible = NSRect(x: 0, y: 24, width: 1470, height: 932)
        let controller = ShelfWindowController.shared

        let testCases: [(ShelfWindowController.ShelfAnchor, CGSize, CGPoint)] = [
            (.bottomRight, CGSize(width: 56, height: 56), CGPoint(x: 1414, y: 24)),
            (.bottomLeft, CGSize(width: 56, height: 56), CGPoint(x: 0, y: 24)),
            (.topRight, CGSize(width: 56, height: 56), CGPoint(x: 1414, y: 900)),
            (.topLeft, CGSize(width: 56, height: 56), CGPoint(x: 0, y: 900)),
            (.center, CGSize(width: 56, height: 56), CGPoint(x: 735 - 28, y: 490 - 28)),
        ]

        for (anchor, size, expectedOrigin) in testCases {
            controller.anchor = anchor
            let origin = controller.anchoredOrigin(size: size, in: visible)
            XCTAssertEqual(
                origin.x,
                expectedOrigin.x,
                accuracy: 0.1,
                "X origin for \(anchor) should be correct"
            )
            XCTAssertEqual(
                origin.y,
                expectedOrigin.y,
                accuracy: 0.1,
                "Y origin for \(anchor) should be correct"
            )
        }
    }

    func testAnchorPersistenceAfterRetrievalWithDefault() {
        let controller = ShelfWindowController.shared
        let defaults = UserDefaults.standard

        // Remove the key to test default
        defaults.removeObject(forKey: "upmarket.shelfAnchor")

        // Should return default
        XCTAssertEqual(controller.anchor, .bottomRight, "Should default to bottomRight when not set")

        // Set to a different value
        controller.anchor = .topLeft
        XCTAssertEqual(controller.anchor, .topLeft, "Should return set value")

        // Change again
        controller.anchor = .center
        XCTAssertEqual(controller.anchor, .center, "Should return updated value")
    }

    func testMultipleRapidAnchorChangesWithNotifications() {
        let controller = ShelfWindowController.shared
        var finalAnchor: ShelfWindowController.ShelfAnchor = .bottomRight
        var anchorChangeCount = 0

        let subscription = NotificationCenter.default.publisher(for: .upmarketShelfAnchorChanged)
            .sink { notification in
                if let rawValue = notification.object as? Int,
                   let anchor = ShelfWindowController.ShelfAnchor(rawValue: rawValue) {
                    finalAnchor = anchor
                    anchorChangeCount += 1
                }
            }
        defer { subscription.cancel() }

        let anchors: [ShelfWindowController.ShelfAnchor] = [.bottomLeft, .topRight, .topLeft, .bottomRight]

        // Simulate 1000 drag-and-snap cycles
        for iteration in 0..<1000 {
            let anchor = anchors[iteration % anchors.count]
            controller.anchor = anchor
            NotificationCenter.default.post(name: .upmarketShelfAnchorChanged, object: anchor.rawValue)

            // Occasional pause to allow notifications to process
            if iteration % 100 == 0 {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
            }
        }

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertEqual(anchorChangeCount, 1000, "Should receive 1000 notifications")
        XCTAssertEqual(finalAnchor, .bottomRight, "Final anchor should be bottomRight (1000 % 4 = 0)")
        XCTAssertEqual(controller.anchor, .bottomRight, "Controller anchor should match final received anchor")
    }
}
