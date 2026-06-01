import Foundation

enum ConversionError: Error, Equatable, LocalizedError {
    case inaccessible
    case passwordRequired
    case cancelled
    case noProgress
    case fileTooLarge
    case pythonRuntime(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .inaccessible:
            return "Upmarket couldn't access this file. Please try again."
        case .passwordRequired:
            return "This PDF is password-protected."
        case .cancelled:
            return "Conversion cancelled."
        case .noProgress:
            return "Conversion made no progress."
        case .fileTooLarge:
            return "This document is too large to convert safely."
        case .pythonRuntime:
            return "The conversion engine couldn't start. Please try again."
        case .failed(let message):
            return message
        }
    }
}
