import Foundation

enum ParserLimitError: Error, CustomStringConvertible {
    case exceeded(String)

    var description: String {
        switch self {
        case .exceeded(let what): return "Parser safety limit exceeded: \(what)"
        }
    }
}

enum ParserLimits {
    static let maxZipArchiveBytes = 512 * 1024 * 1024
    static let maxZipPartUncompressedBytes = 512 * 1024 * 1024
    static let maxZipPackageUncompressedBytes = 2 * 1024 * 1024 * 1024

    static let excelMaxColumns = 16_384
    static let excelMaxRows = 1_048_576
    static let maxMarkdownTableRows = 10_000
    static let maxMarkdownTableColumns = 1_024
    static let maxMarkdownTableCells = 200_000

    static let maxSharedStrings = 1_000_000
    static let maxSharedStringBytes = 512 * 1024 * 1024
    static let maxSharedStringLength = 1 * 1024 * 1024

    static let maxPowerPointRecordDepth = 128
    static let maxWordTableDepth = 64
    static let maxCompoundStreamBytes = 512 * 1024 * 1024
}
