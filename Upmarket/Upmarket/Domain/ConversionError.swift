import Foundation

enum ConversionError: Error, Equatable, LocalizedError {
    case inaccessible
    case passwordRequired
    case cancelled
    case noProgress
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
        case .pythonRuntime(let message), .failed(let message):
            return message
        }
    }
}
