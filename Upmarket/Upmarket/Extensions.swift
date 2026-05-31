import Foundation

extension Notification.Name {
    static let openFilePicker            = Notification.Name("upmarket.openFilePicker")
    static let upmarketReprocessItem     = Notification.Name("upmarket.reprocessItem")
    static let upmarketConversionStarted = Notification.Name("upmarket.conversionStarted")
    static let upmarketConversionEnded   = Notification.Name("upmarket.conversionEnded")
}

struct ReprocessRequest {
    let url: URL
    let itemID: UUID
    let useAI: Bool
    let enhanced: Bool
}
