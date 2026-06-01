import XCTest
import PythonKit
@testable import Upmarket

final class PythonBridgeTests: XCTestCase {
    func testBridgeErrorsAreTypedAndUserReadable() {
        XCTAssertEqual(
            PythonBridgeError.frameworkNotFound.localizedDescription,
            "Conversion runtime is missing from the app bundle."
        )
        XCTAssertEqual(
            PythonBridgeError.moduleUnavailable("docling_bridge.converter").localizedDescription,
            "Conversion component unavailable: docling_bridge.converter"
        )
        XCTAssertEqual(
            PythonBridgeError.callFailed("boom").localizedDescription,
            "Conversion component failed: boom"
        )
        XCTAssertEqual(PythonBridgeError.frameworkNotFound.diagnosticCode, "runtime.bridge.missing")
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

    @MainActor
    func testEmbeddedRuntimeImportsPackagedConverterOnRuntimeThread() async throws {
        let moduleName = try await PythonRuntime.shared.withPython {
            let converter = Python.import("docling_bridge.converter")
            return String(converter.__name__) ?? "unknown"
        }

        XCTAssertEqual(moduleName, "docling_bridge.converter")
    }
}
