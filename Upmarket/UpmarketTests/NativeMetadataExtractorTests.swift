import CoreGraphics
import ImageIO
import XCTest
@testable import Upmarket

final class NativeMetadataExtractorTests: XCTestCase {
    func testImageMetadataUsesNativeImageIO() throws {
        let workspace = try AppWorkspace.create(prefix: "native-metadata-test")
        defer { AppWorkspace.remove(workspace) }

        let imageURL = workspace.appendingPathComponent("sample.png")
        try writePNG(to: imageURL)

        let result = NativeMetadataExtractor.imageMetadata(url: imageURL, title: "sample")

        guard case .success(let output) = result else {
            return XCTFail("Expected native image metadata extraction to succeed")
        }
        XCTAssertTrue(output.markdown.contains("# Image: sample"))
        XCTAssertTrue(output.markdown.contains("**Dimensions:** 1 x 1 px"))
        XCTAssertEqual(output.format, "PNG")
    }

    func testCorpusMediaMetadataUsesNativeAVFoundation() async throws {
        let fixtures = [
            "tests/data/audio/sample_10s_audio-flac.flac",
            "tests/data/audio/sample_10s_video-mp4.mp4",
            "tests/data/audio/sample_10s_video-quicktime.mov"
        ]

        for relativePath in fixtures {
            let url = corpusDoclingPath.appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw XCTSkip("Docling corpus not available - run: git submodule update --init")
            }

            let result = await NativeMetadataExtractor.mediaMetadata(
                url: url,
                title: url.deletingPathExtension().lastPathComponent
            )

            guard case .success(let output) = result else {
                return XCTFail("Expected AVFoundation metadata extraction for \(relativePath)")
            }
            XCTAssertTrue(output.markdown.contains("# Media:"))
            XCTAssertTrue(output.markdown.contains("**Duration:**"))
            XCTAssertEqual(output.format, url.pathExtension.uppercased())
            XCTAssertEqual(output.pipeline, .fast)
        }
    }

    func testWorkspaceIsAppOwned() throws {
        let workspace = try AppWorkspace.create(prefix: "workspace-test")
        defer { AppWorkspace.remove(workspace) }

        XCTAssertTrue(workspace.path.contains("/Library/Application Support/Upmarket/Workspaces/"))
        XCTAssertFalse(workspace.path.hasPrefix("/private/tmp/"))
    }

    private func writePNG(to url: URL) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "NativeMetadataExtractorTests", code: 1)
        }
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw NSError(domain: "NativeMetadataExtractorTests", code: 2)
        }
        CGImageDestinationAddImage(destination, image, nil)
        if !CGImageDestinationFinalize(destination) {
            throw NSError(domain: "NativeMetadataExtractorTests", code: 3)
        }
    }

    private var corpusDoclingPath: URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("tests/corpus/docling/docling")
    }
}
