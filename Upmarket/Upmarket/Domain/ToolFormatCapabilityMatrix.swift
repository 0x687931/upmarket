import Foundation

enum ConversionTool: String, CaseIterable, Sendable {
    case pdfKit
    case vision
    case speech
    case imageIO
    case avFoundation
    case pythonPDFium
    case markItDown
    case enhanced
    case upmarketAI
}

enum ConversionFormat: String, CaseIterable, Sendable {
    case pdf
    case docx
    case pptx
    case xlsx
    case html
    case md
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

    init?(fileExtension: String) {
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
        add(.pythonPDFium, [.pdf], .fallback, advanced: true)
        add(.markItDown, [.docx, .pptx, .xlsx, .html, .md, .csv, .json, .xml, .epub, .zip, .webvtt, .png, .jpg, .jpeg, .mp3, .m4a, .wav], .fallback, advanced: true)
        add(.enhanced, [.pdf, .docx, .pptx, .xlsx, .html, .md, .asciidoc, .epub, .xml, .png, .jpg, .jpeg, .tif, .tiff, .webp], .primary, advanced: true)
        add(.upmarketAI, [.pdf, .png, .jpg, .jpeg, .tif, .tiff, .webp], .primary, advanced: true)

        return entries
    }()

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
