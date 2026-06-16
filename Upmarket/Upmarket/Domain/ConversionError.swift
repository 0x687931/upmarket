import Foundation

enum ConversionError: Error, Equatable, LocalizedError {
    case inaccessible
    case passwordRequired
    case cancelled
    case noProgress
    case memoryPressure
    case fileTooLarge
    case sourceUnavailable
    case unsupportedOnThisMac
    case modelUnavailable
    case downloadFailed
    case upgradeRequired
    case engineFailed(String)
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
        case .memoryPressure:
            return "system.memory-pressure"
        case .fileTooLarge:
            return "file.too-large"
        case .sourceUnavailable:
            return "file.unavailable"
        case .unsupportedOnThisMac:
            return "device.unsupported-conversion"
        case .modelUnavailable:
            return "model.unavailable"
        case .downloadFailed:
            return "model.download-failed"
        case .upgradeRequired:
            return "entitlement.upgrade-required"
        case .engineFailed:
            return "engine.failed"
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
        case .memoryPressure:
            return "Conversion paused because this Mac is low on memory. Retry after closing other apps."
        case .fileTooLarge:
            return "This document is too large to convert safely."
        case .sourceUnavailable:
            return "This document is not available on this Mac. Download it and try again."
        case .unsupportedOnThisMac:
            return "This conversion is not supported on this Mac."
        case .modelUnavailable:
            return "The AI model isn't installed. Download it in Settings to convert this document."
        case .downloadFailed:
            return "Model download failed. Check your connection and try again from Settings."
        case .upgradeRequired:
            return "This document needs AI or Enhanced conversion. Upgrade to Pro to convert it."
        case .engineFailed:
            return "The conversion engine couldn't start. Please try again."
        case .failed(let message):
            return message
        }
    }
}
