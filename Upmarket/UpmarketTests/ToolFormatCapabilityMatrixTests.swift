import XCTest
@testable import Upmarket

final class ToolFormatCapabilityMatrixTests: XCTestCase {
    func testAudioFormatsExposeAllValidRoutes() {
        for format in [ConversionFormat.mp3, .m4a, .wav] {
            let tools = Set(ToolFormatCapabilityMatrix.tools(for: format))

            XCTAssertTrue(tools.contains(.speech), "\(format.rawValue) should be valid for native Speech")
            XCTAssertTrue(tools.contains(.markItDown), "\(format.rawValue) should be valid for MarkItDown fallback evaluation")
            XCTAssertTrue(tools.contains(.avFoundation), "\(format.rawValue) should be valid for AVFoundation metadata")
        }
    }

    func testPDFFormatsExposeNativeAndPythonRoutes() {
        let tools = Set(ToolFormatCapabilityMatrix.tools(for: .pdf))

        XCTAssertTrue(tools.contains(.pdfKit))
        XCTAssertTrue(tools.contains(.vision))
        XCTAssertTrue(tools.contains(.pythonPDFium))
        XCTAssertTrue(tools.contains(.enhanced))
        XCTAssertTrue(tools.contains(.upmarketAI))
    }

    func testUnsupportedToolFormatPairIsNotInvented() {
        XCTAssertFalse(ToolFormatCapabilityMatrix.supports(.pdfKit, .mp3))
        XCTAssertFalse(ToolFormatCapabilityMatrix.supports(.speech, .pdf))
    }
}
