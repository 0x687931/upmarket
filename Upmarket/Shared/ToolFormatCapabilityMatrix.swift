import Foundation
import UniformTypeIdentifiers

enum ConversionTool: String, CaseIterable, Sendable {
    case pdfKit
    case vision
    case speech
    case imageIO
    case avFoundation
    case swiftOffice    // SwiftOfficeMarkdown — native OOXML/legacy Office
    case nativeText     // in-process .txt/.md/.csv
    case nativeHTML     // in-process libxml2 HTML
    case upmarketAI     // native Granite-Docling (mlx-swift)
}

enum ConversionFormat: String, CaseIterable, Sendable {
    case pdf
    case docx
    case pptx
    case xlsx
    case doc
    case xls
    case ppt
    case html
    case md
    case txt
    case asciidoc
    case epub
    case csv
    case json
    case xml
    case zip
    case webvtt
    case png
    case jpg
    case jpeg
    case gif
    case tiff
    case tif
    case webp
    case bmp
    case heic
    case heif
    case mp3
    case m4a
    case wav
    case aiff
    case opus
    case flac
    case aac
    case ogg
    case mp4
    case m4v
    case mov
    case avi
    case mpeg
    case mpg
    case webm
    case mkv
    case wma
    case wmv

    nonisolated init?(fileExtension: String) {
        self.init(rawValue: fileExtension.lowercased())
    }
}

struct ToolFormatCapability: Equatable, Sendable {
    enum Support: String, Sendable {
        case primary
        case fallback
        case metadataOnly
        case reference
    }

    let tool: ConversionTool
    let format: ConversionFormat
    let support: Support
    let requiresAdvancedRuntime: Bool
    let requiresAuthorisation: Bool
}

enum ToolFormatCapabilityMatrix {
    nonisolated static let entries: [ToolFormatCapability] = {
        var entries: [ToolFormatCapability] = []

        func add(
            _ tool: ConversionTool,
            _ formats: [ConversionFormat],
            _ support: ToolFormatCapability.Support,
            advanced: Bool = false,
            authorisation: Bool = false
        ) {
            entries.append(contentsOf: formats.map {
                ToolFormatCapability(
                    tool: tool,
                    format: $0,
                    support: support,
                    requiresAdvancedRuntime: advanced,
                    requiresAuthorisation: authorisation
                )
            })
        }

        add(.pdfKit, [.pdf], .primary)
        add(.vision, [.pdf, .png, .jpg, .jpeg, .tiff, .tif, .heic, .heif], .primary)
        add(.speech, [.mp3, .m4a, .wav, .aiff, .opus], .primary, authorisation: true)
        add(.imageIO, [.png, .jpg, .jpeg, .gif, .tiff, .tif, .webp, .bmp, .heic, .heif], .metadataOnly)
        add(.avFoundation, [.mp3, .m4a, .wav, .aiff, .opus, .flac, .aac, .ogg, .mp4, .m4v, .mov, .avi, .mpeg, .mpg, .webm, .mkv, .wma, .wmv], .metadataOnly)
        add(.swiftOffice, [.docx, .pptx, .xlsx, .doc, .xls, .ppt], .primary)
        add(.nativeText, [.md, .txt, .csv], .primary)
        add(.nativeHTML, [.html], .primary)
        add(.upmarketAI, [.pdf, .png, .jpg, .jpeg, .tif, .tiff, .webp], .primary, advanced: true)

        return entries
    }()

    nonisolated static let acceptedFormats: [ConversionFormat] = {
        // Formats with a native engine. EPUB/JSON/XML/ZIP/WEBVTT were Python-only and are
        // no longer supported after the Python runtime removal.
        let productSurface: Set<ConversionFormat> = [
            .pdf, .html, .txt, .csv, .png, .jpg, .jpeg, .gif, .tiff,
            .docx, .pptx, .xlsx, .doc, .xls, .ppt,
            .mp3, .m4a, .wav, .aiff, .opus,
        ]
        return ConversionFormat.allCases.filter {
            productSurface.contains($0) && !capabilities(for: $0).isEmpty
        }
    }()

    nonisolated static let acceptedFileExtensions: [String] = acceptedFormats.map(\.rawValue)

    nonisolated static let acceptedTypeIdentifiers: [String] = acceptedFileExtensions.compactMap {
        UTType(filenameExtension: $0)?.identifier
    }

    nonisolated static let acceptedContentTypes: [UTType] = acceptedTypeIdentifiers.compactMap(UTType.init)

    nonisolated static func accepts(fileExtension: String) -> Bool {
        guard let format = ConversionFormat(fileExtension: fileExtension) else { return false }
        return acceptedFormats.contains(format)
    }

    nonisolated static func hasCapability(fileExtension: String) -> Bool {
        guard let format = ConversionFormat(fileExtension: fileExtension) else { return false }
        return !capabilities(for: format).isEmpty
    }

    nonisolated static func accepts(_ url: URL) -> Bool {
        guard let ownType = UTType(filenameExtension: url.pathExtension) else { return false }
        return acceptedContentTypes.contains { ownType.conforms(to: $0) }
    }

    nonisolated static func capabilities(for format: ConversionFormat) -> [ToolFormatCapability] {
        entries.filter { $0.format == format }
    }

    nonisolated static func tools(for format: ConversionFormat) -> [ConversionTool] {
        capabilities(for: format).map(\.tool)
    }

    nonisolated static func supports(_ tool: ConversionTool, _ format: ConversionFormat) -> Bool {
        entries.contains { $0.tool == tool && $0.format == format }
    }
}
