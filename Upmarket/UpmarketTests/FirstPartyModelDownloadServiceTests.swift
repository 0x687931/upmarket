import CryptoKit
import XCTest
@testable import Upmarket

final class FirstPartyModelDownloadServiceTests: XCTestCase {

    func testUpmarketAIFirstPartyManifestInstallsCompleteRuntimeMetadata() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("upmarket-first-party-model-\(UUID().uuidString)", isDirectory: true)
        let sourceRoot = root.appendingPathComponent("source", isDirectory: true)
        let downloadRoot = root.appendingPathComponent("downloads", isDirectory: true)
        let modelsRoot = root.appendingPathComponent("models", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let expectedFiles = [
            "added_tokens.json",
            "chat_template.jinja",
            "config.json",
            "generation_config.json",
            "merges.txt",
            "model.safetensors",
            "model.safetensors.index.json",
            "preprocessor_config.json",
            "processor_config.json",
            "special_tokens_map.json",
            "tokenizer.json",
            "tokenizer_config.json",
            "vocab.json",
        ]

        try FileManager.default.createDirectory(
            at: sourceRoot.appendingPathComponent("granite_docling", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: downloadRoot, withIntermediateDirectories: true)

        var files: [[String: Any]] = []
        for relative in expectedFiles {
            let url = sourceRoot.appendingPathComponent("granite_docling").appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let content = Data("fixture-\(relative)".utf8)
            try content.write(to: url)
            files.append([
                "path": relative,
                "url": "granite_docling/\(relative)",
                "sha256": Self.sha256Hex(for: content),
                "bytes": content.count,
            ])
        }

        let sourceManifest: [String: Any] = [
            "manifest_version": 1,
            "model_key": "granite_docling",
            "source_id": "com.upmarket.models.granite-docling",
            "revision": "e9939db25d2f296c8678d0491c4609a8c596c50a",
            "storage_dir": "granite_docling",
            "expected_files": expectedFiles,
            "expected_dirs": [],
            "files": files,
        ]
        let manifestData = try JSONSerialization.data(withJSONObject: sourceManifest, options: [.prettyPrinted])
        try manifestData.write(to: sourceRoot.appendingPathComponent("granite_docling.json"))

        let service = FirstPartyModelDownloadService(
            modelsDirectoryURL: modelsRoot,
            manifestBaseURL: { sourceRoot },
            dataLoader: { url in
                try Data(contentsOf: url)
            },
            fileDownloader: { url in
                let destination = downloadRoot.appendingPathComponent(UUID().uuidString)
                try FileManager.default.copyItem(at: url, to: destination)
                return destination
            }
        )

        let result = await service.downloadModel(key: "granite_docling", progressFile: "")
        XCTAssertTrue(result.success, result.error ?? "download failed")

        let installed = modelsRoot.appendingPathComponent("granite_docling", isDirectory: true)
        XCTAssertTrue(FileManager.default.isReadableFile(atPath: installed.appendingPathComponent("chat_template.jinja").path))
        XCTAssertTrue(FileManager.default.isReadableFile(atPath: installed.appendingPathComponent("tokenizer_config.json").path))

        let validationManifestURL = installed.appendingPathComponent("upmarket_manifest.json")
        let validationManifest = try JSONSerialization.jsonObject(
            with: Data(contentsOf: validationManifestURL)
        ) as? [String: Any]
        XCTAssertEqual(validationManifest?["source_id"] as? String, "com.upmarket.models.granite-docling")
        XCTAssertEqual(validationManifest?["expected_files"] as? [String], expectedFiles)

        let manifestFiles = validationManifest?["files"] as? [String: String]
        XCTAssertNotNil(manifestFiles?["chat_template.jinja"])
        XCTAssertNotNil(manifestFiles?["tokenizer_config.json"])
    }

    private static func sha256Hex(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
