import XCTest
@testable import Upmarket

final class ToolFormatCapabilityMatrixTests: XCTestCase {
    func testAudioFormatsExposeAllValidRoutes() {
        for format in [ConversionFormat.mp3, .m4a, .wav] {
            let tools = Set(ToolFormatCapabilityMatrix.tools(for: format))

            XCTAssertTrue(tools.contains(.speech), "\(format.rawValue) should be valid for native Speech")
            XCTAssertTrue(tools.contains(.avFoundation), "\(format.rawValue) should be valid for AVFoundation metadata")
        }
    }

    func testPDFFormatsExposeNativeRoutes() {
        let tools = Set(ToolFormatCapabilityMatrix.tools(for: .pdf))

        XCTAssertTrue(tools.contains(.pdfKit))
        XCTAssertTrue(tools.contains(.vision))
        XCTAssertTrue(tools.contains(.upmarketAI))
    }

    func testPlainTextIsAcceptedThroughNativeTextRoute() {
        let tools = Set(ToolFormatCapabilityMatrix.tools(for: .txt))

        XCTAssertTrue(tools.contains(.nativeText))
        XCTAssertTrue(ToolFormatCapabilityMatrix.accepts(fileExtension: "txt"))
    }

    func testNativeMediaMetadataCapabilitiesAreTrackedWithoutExpandingProductSurface() {
        XCTAssertTrue(ToolFormatCapabilityMatrix.supports(.avFoundation, .flac))
        XCTAssertTrue(ToolFormatCapabilityMatrix.supports(.avFoundation, .mov))
        XCTAssertFalse(ToolFormatCapabilityMatrix.accepts(fileExtension: "flac"))
        XCTAssertFalse(ToolFormatCapabilityMatrix.accepts(fileExtension: "mov"))
    }

    func testAcceptedFormatsAllHaveAtLeastOneRealCapability() {
        for format in ToolFormatCapabilityMatrix.acceptedFormats {
            XCTAssertFalse(
                ToolFormatCapabilityMatrix.capabilities(for: format).isEmpty,
                "\(format.rawValue) must not be accepted without a tool route"
            )
        }
    }

    func testUnsupportedToolFormatPairIsNotInvented() {
        XCTAssertFalse(ToolFormatCapabilityMatrix.supports(.pdfKit, .mp3))
        XCTAssertFalse(ToolFormatCapabilityMatrix.supports(.speech, .pdf))
    }
}
