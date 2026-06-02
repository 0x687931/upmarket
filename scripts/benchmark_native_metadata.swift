import AVFoundation
import Foundation
import ImageIO

struct CorpusDocument: Decodable {
    let id: String
    let file: String
    let category: String
    let format: String
}

struct CorpusManifest: Decodable {
    let documents: [CorpusDocument]
}

@main
struct NativeMetadataBenchmark {
    static func main() async throws {
        let pathway = CommandLine.arguments.dropFirst().first ?? ""
        guard pathway == "swift-imageio-metadata" || pathway == "swift-avfoundation-metadata" else {
            FileHandle.standardError.write(Data("usage: benchmark_native_metadata.swift swift-imageio-metadata|swift-avfoundation-metadata\n".utf8))
            Foundation.exit(2)
        }

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let corpus = root.appendingPathComponent("tests/corpus")
        let manifestURL = corpus.appendingPathComponent("manifest.json")
        let manifest = try JSONDecoder().decode(CorpusManifest.self, from: Data(contentsOf: manifestURL))

        let imageFormats: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "webp", "tif", "tiff", "bmp", "gif"]
        let mediaFormats: Set<String> = ["flac", "avi", "mov", "ogg", "aac", "wma", "wmv", "mkv", "m4v", "mp4", "mpeg", "mpg", "webm"]

        for document in manifest.documents {
            let isHandled = pathway == "swift-imageio-metadata"
                ? document.category == "image" && imageFormats.contains(document.format)
                : ["audio", "video"].contains(document.category) && mediaFormats.contains(document.format)
            guard isHandled else { continue }

            let fileURL = resolve(document.file, corpus: corpus)
            let started = Date()
            let output: (markdown: String, error: String?)
            if pathway == "swift-imageio-metadata" {
                output = imageMetadata(url: fileURL, title: fileURL.deletingPathExtension().lastPathComponent)
            } else {
                output = await mediaMetadata(url: fileURL, title: fileURL.deletingPathExtension().lastPathComponent)
            }
            let elapsed = Date().timeIntervalSince(started)
            let row: [String: Any] = [
                "id": document.id,
                "file": document.file,
                "category": document.category,
                "markdown": output.markdown,
                "elapsed_seconds": elapsed,
                "error": output.error as Any
            ]
            let data = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }

    private static func resolve(_ relativePath: String, corpus: URL) -> URL {
        let direct = corpus.appendingPathComponent(relativePath)
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        return corpus.appendingPathComponent("docling/docling").appendingPathComponent(relativePath)
    }

    private static func imageMetadata(url: URL, title: String) -> (markdown: String, error: String?) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return ("", "Upmarket couldn't read this image file.")
        }
        let width = properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0
        let type = CGImageSourceGetType(source).map { $0 as String } ?? url.pathExtension.uppercased()
        let markdown = [
            "# Image: \(title)",
            "",
            "**Format:** \(type)  ",
            "**Dimensions:** \(width) x \(height) px  "
        ].joined(separator: "\n")
        return (markdown, nil)
    }

    private static func mediaMetadata(url: URL, title: String) async -> (markdown: String, error: String?) {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let tracks = try await asset.load(.tracks)
            let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            var lines = [
                "# Media: \(title)",
                "",
                "**Duration:** \(format(duration))  ",
                "**Size:** \(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))  "
            ]

            for track in tracks {
                let mediaType = track.mediaType
                let formatDescriptions = try await track.load(.formatDescriptions)
                let codec = formatDescriptions.first.map { CMFormatDescriptionGetMediaSubType($0).fourCCString } ?? "unknown"
                if mediaType == .audio {
                    lines.append("**Audio:** \(codec)  ")
                } else if mediaType == .video {
                    let size = try await track.load(.naturalSize)
                    let frameRate = try await track.load(.nominalFrameRate)
                    lines.append("**Video:** \(codec), \(Int(size.width)) x \(Int(size.height)), \(String(format: "%.2f", frameRate)) fps  ")
                }
            }
            return (lines.joined(separator: "\n"), nil)
        } catch {
            return ("", "Upmarket couldn't read this media file.")
        }
    }

    private static func format(_ time: CMTime) -> String {
        let total = max(0, Int(CMTimeGetSeconds(time).rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private extension FourCharCode {
    var fourCCString: String {
        let bytes = [
            UInt8((self >> 24) & 0xff),
            UInt8((self >> 16) & 0xff),
            UInt8((self >> 8) & 0xff),
            UInt8(self & 0xff)
        ]
        let scalars = bytes.map { byte -> UnicodeScalar in
            byte >= 32 && byte <= 126 ? UnicodeScalar(byte) : "."
        }
        return String(String.UnicodeScalarView(scalars))
    }
}
