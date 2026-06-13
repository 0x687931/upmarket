import CoreGraphics
import Foundation

enum VisionProcessingLimitError: LocalizedError {
    case invalidPageBounds
    case tooManyPages(Int)
    case imageTooLarge(Int)
    case pageTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidPageBounds:
            return "Upmarket couldn't process this page."
        case .tooManyPages, .imageTooLarge, .pageTooLarge:
            return "This document is too large to process safely."
        }
    }
}

struct VisionProcessingLimits {
    static let maximumOCRPages = 80
    static let maximumPDFKitPages = 1_000
    static let maximumRenderedPixels = 16_000_000
    static let maximumImagePixels = 40_000_000
    static let maximumRenderedSide = 4_096
    static let maximumPDFPageSidePoints: CGFloat = 14_400
    static let maximumPDFPageAreaPoints: CGFloat = 50_000_000

    static func validatePageCount(_ pageCount: Int) throws {
        if pageCount > maximumOCRPages {
            throw VisionProcessingLimitError.tooManyPages(pageCount)
        }
    }

    static func validatePDFKitPageCount(_ pageCount: Int, maximum: Int = maximumPDFKitPages) throws {
        if pageCount > maximum {
            throw VisionProcessingLimitError.tooManyPages(pageCount)
        }
    }

    static func validatePDFPageBounds(
        _ bounds: CGRect,
        maximumSide: CGFloat = maximumPDFPageSidePoints,
        maximumArea: CGFloat = maximumPDFPageAreaPoints
    ) throws {
        guard bounds.width.isFinite,
              bounds.height.isFinite,
              bounds.width > 0,
              bounds.height > 0 else {
            throw VisionProcessingLimitError.invalidPageBounds
        }
        if bounds.width > maximumSide || bounds.height > maximumSide {
            throw VisionProcessingLimitError.pageTooLarge
        }
        if bounds.width * bounds.height > maximumArea {
            throw VisionProcessingLimitError.pageTooLarge
        }
    }

    static func validateImagePixels(width: Int, height: Int) throws {
        guard width > 0, height > 0 else { throw VisionProcessingLimitError.invalidPageBounds }
        let pixels = width * height
        if pixels > maximumImagePixels {
            throw VisionProcessingLimitError.imageTooLarge(pixels)
        }
    }

    static func renderSize(for bounds: CGRect, dpi: CGFloat) throws -> (width: Int, height: Int) {
        guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
            throw VisionProcessingLimitError.invalidPageBounds
        }

        let baseScale = dpi / 72.0
        var width = max(Int(bounds.width * baseScale), 1)
        var height = max(Int(bounds.height * baseScale), 1)
        let longestSide = max(width, height)
        if longestSide > maximumRenderedSide {
            let ratio = CGFloat(maximumRenderedSide) / CGFloat(longestSide)
            width = max(Int(CGFloat(width) * ratio), 1)
            height = max(Int(CGFloat(height) * ratio), 1)
        }

        let pixels = width * height
        if pixels > maximumRenderedPixels {
            let ratio = sqrt(CGFloat(maximumRenderedPixels) / CGFloat(pixels))
            width = max(Int(CGFloat(width) * ratio), 1)
            height = max(Int(CGFloat(height) * ratio), 1)
        }

        return (width, height)
    }
}
