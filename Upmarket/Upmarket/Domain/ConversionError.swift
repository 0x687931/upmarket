import Foundation

enum ConversionError: Error, Equatable, LocalizedError {
    case inaccessible
    case passwordRequired
    case cancelled
    case noProgress
    case fileTooLarge
    case sourceUnavailable
    case pythonRuntime(String)
    case failed(String)

    var diagnosticCode: String {
        switch self {
        case .inaccessible:
            return "file.access"
        case .passwordRequired:
            return "file.password"
        case .cancelled:
            return "job.cancelled"
        case .noProgress:
            return "job.no-progress"
        case .fileTooLarge:
            return "file.too-large"
        case .sourceUnavailable:
            return "file.unavailable"
        case .pythonRuntime:
            return "runtime.bridge"
        case .failed:
            return "conversion.failed"
        }
    }

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
        case .sourceUnavailable:
            return "This document is not available on this Mac. Download it and try again."
        case .pythonRuntime:
            return "The conversion engine couldn't start. Please try again."
        case .failed(let message):
            return message
        }
    }
}
