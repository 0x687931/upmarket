import XCTest
@testable import Upmarket

final class PythonBridgeTests: XCTestCase {
    func testBridgeErrorsAreTypedAndUserReadable() {
        XCTAssertEqual(
            PythonBridgeError.frameworkNotFound.localizedDescription,
            "Python.framework not found in app bundle."
        )
        XCTAssertEqual(
            PythonBridgeError.moduleUnavailable("docling_bridge.converter").localizedDescription,
            "Python module unavailable: docling_bridge.converter"
        )
        XCTAssertEqual(
            PythonBridgeError.callFailed("boom").localizedDescription,
            "Python call failed: boom"
        )
    }

    @MainActor
    func testRuntimeStatusReportsReadiness() async {
        await PythonRuntime.shared.setup()
        let status = await PythonRuntime.shared.status()

        if status.isReady {
            XCTAssertNotNil(status.version)
            XCTAssertNil(status.error)
        } else {
            XCTAssertNotNil(status.error)
        }
    }
}
