import Foundation

/// Shorthand for NSLocalizedString — use L("key") throughout the app.
/// Falls back to English if the user's language isn't available.
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = NSLocalizedString(key, tableName: "Localizable", bundle: .main, comment: "")
    return args.isEmpty ? format : String(format: format, arguments: args)
}

/// SwiftUI Text wrapper for localised strings.
/// Usage: LText("dropzone.title")
import SwiftUI

func LText(_ key: String, _ args: CVarArg...) -> Text {
    Text(verbatim: L(key, args))
}
