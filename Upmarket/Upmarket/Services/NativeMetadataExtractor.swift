import AVFoundation
import Foundation
import ImageIO

enum NativeMetadataExtractor {
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "webp", "tif", "tiff", "bmp", "gif"
    ]

    private static let mediaExtensions: Set<String> = [
        "flac", "avi", "mov", "ogg", "aac", "wma", "wmv", "mkv", "m4v",
        "mp4", "mpeg", "mpg", "webm"
    ]

    static func handlesImage(_ ext: String) -> Bool {
        imageExtensions.contains(ext.lowercased())
    }

    static func handlesMedia(_ ext: String) -> Bool {
        mediaExtensions.contains(ext.lowercased())
    }

    static func imageMetadata(url: URL, title: String) -> ConversionResult {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return .failure("Upmarket couldn't read this image file.")
        }

        let width = properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0
        let type = CGImageSourceGetType(source).map { $0 as String } ?? url.pathExtension.uppercased()

        var lines = [
            "# Image: \(title)",
            "",
            "**Format:** \(type)  ",
            "**Dimensions:** \(width) x \(height) px  "
        ]

        let flattened = flattenImageMetadata(properties)
        let keys = [
            "TIFF.Make", "TIFF.Model", "TIFF.Software", "Exif.DateTimeOriginal",
            "Exif.LensModel", "GPS.Latitude", "GPS.Longitude", "PNG.Title",
            "PNG.Author", "IPTC.ObjectName", "IPTC.Byline", "IPTC.CopyrightNotice"
        ]
        let metadataLines = keys.compactMap { key -> String? in
            guard let value = flattened[key], !value.isEmpty else { return nil }
            return "**\(key):** \(value)"
        }

        if !metadataLines.isEmpty {
            lines.append("")
            lines.append("## Metadata")
            lines.append(contentsOf: metadataLines)
        }

        return .success(ConversionOutput(
            markdown: lines.joined(separator: "\n"),
            pages: 1,
            format: url.pathExtension.uppercased(),
            title: title,
            pipeline: .fast
        ))
    }

    static func mediaMetadata(url: URL, title: String) async -> ConversionResult {
        let asset = AVURLAsset(url: url)

        do {
            let duration = try await asset.load(.duration)
            let tracks = try await asset.load(.tracks)
            let metadata = try await asset.load(.commonMetadata)
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

            var tags: [String] = []
            for item in metadata {
                if let line = await metadataLine(item) {
                    tags.append(line)
                }
            }
            if !tags.isEmpty {
                lines.append("")
                lines.append("## Tags")
                lines.append(contentsOf: tags)
            }

            return .success(ConversionOutput(
                markdown: lines.joined(separator: "\n"),
                pages: 1,
                format: url.pathExtension.uppercased(),
                title: title,
                pipeline: .fast
            ))
        } catch {
            return .failure("Upmarket couldn't read this media file.")
        }
    }

    private static func flattenImageMetadata(_ properties: [String: Any]) -> [String: String] {
        let groups: [(String, CFString)] = [
            ("TIFF", kCGImagePropertyTIFFDictionary),
            ("Exif", kCGImagePropertyExifDictionary),
            ("GPS", kCGImagePropertyGPSDictionary),
            ("PNG", kCGImagePropertyPNGDictionary),
            ("IPTC", kCGImagePropertyIPTCDictionary)
        ]

        var output: [String: String] = [:]
        for (prefix, key) in groups {
            guard let values = properties[key as String] as? [String: Any] else { continue }
            for (name, value) in values {
                output["\(prefix).\(name)"] = String(describing: value)
            }
        }
        return output
    }

    nonisolated private static func metadataLine(_ item: AVMetadataItem) async -> String? {
        guard let key = item.commonKey?.rawValue,
              ["title", "artist", "albumName", "description", "creationDate", "copyrights"].contains(key),
              let value = try? await item.load(.stringValue),
              !value.isEmpty else { return nil }
        return "**\(key):** \(value)"
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
