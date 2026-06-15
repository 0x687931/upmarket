import Foundation

/// Interprets Excel number-format codes enough to render cell values correctly
/// in Markdown — chiefly turning **date serials into ISO dates** and
/// **fractions into percentages**. Shared by the xlsx, xlsb, and xls parsers
/// (which differ only in how they obtain a cell's format id / custom code).
///
/// This is intentionally a pragmatic subset: ISO output rather than honoring the
/// exact code layout, since unambiguous dates/percentages are what matter for
/// Markdown. Builtin ids follow ECMA-376 §18.8.30.
enum ExcelNumberFormat {
    enum Kind { case date, time, dateTime, percent, number }

    /// Builtin `numFmtId` → kind; nil for ids ≥ 164 (custom — consult the code).
    static func builtinKind(_ id: Int) -> Kind? {
        switch id {
        case 14, 15, 16, 17:               return .date
        case 22:                           return .dateTime
        case 18, 19, 20, 21, 45, 46, 47:   return .time
        case 9, 10:                        return .percent
        case 0..<164:                      return .number   // general / numeric / text
        default:                           return nil       // custom
        }
    }

    static func kind(numFmtId: Int, code: String?) -> Kind {
        if let builtin = builtinKind(numFmtId) { return builtin }
        guard let code, !code.isEmpty else { return .number }
        return kind(forCode: code)
    }

    /// Detect kind from a custom format code by scanning its significant tokens.
    static func kind(forCode code: String) -> Kind {
        let tokens = significantTokens(code)
        if tokens.contains("%") { return .percent }
        let t = tokens.lowercased()
        let hasDate = t.contains("y") || t.contains("d")
        let hasTime = t.contains("h") || t.contains("s")
        if hasDate && hasTime { return .dateTime }
        if hasDate { return .date }
        if hasTime { return .time }
        if t.contains("m") { return .date }     // lone m/mm → month
        return .number
    }

    /// Render a numeric cell value per its number format.
    static func format(value: Double, numFmtId: Int, code: String?, date1904: Bool = false) -> String {
        switch kind(numFmtId: numFmtId, code: code) {
        case .date:     return isoDate(value, withTime: false, date1904: date1904)
        case .dateTime: return isoDate(value, withTime: true, date1904: date1904)
        case .time:     return isoTime(value)
        case .percent:  return number(value * 100) + "%"
        case .number:
            let n = number(value)
            if let code, let symbol = currencySymbol(in: code) { return symbol + n }
            return n
        }
    }

    // MARK: - Currency

    /// Single-scalar currency symbols we recognise when written literally.
    private static let currencyScalars: Set<Unicode.Scalar> =
        ["$", "£", "¥", "€", "₩", "₹", "₽", "฿", "₪", "₫", "₴", "₦", "₱", "₡", "₲", "₵"]

    /// Locale id (in `[$-XXX]`) → currency symbol, for the locale-only form.
    private static let localeCurrency: [Int: String] = [
        0x409: "$", 0x1009: "$", 0x0C09: "$", 0x809: "£", 0x452: "£", 0x411: "¥",
        0x407: "€", 0x40C: "€", 0x410: "€", 0x40A: "€", 0x413: "€", 0x816: "€",
    ]

    /// Extract a currency symbol from a format code, or nil. Handles the
    /// `[$SYMBOL-locale]` form (incl. locale-only), and bare/quoted symbols.
    static func currencySymbol(in code: String) -> String? {
        if let r = code.range(of: "[$") {
            let after = code[r.upperBound...]
            let end = after.firstIndex(where: { $0 == "-" || $0 == "]" }) ?? after.endIndex
            let explicit = String(after[..<end])
            if !explicit.isEmpty { return explicit }       // [$£-809] → "£", [$$-409] → "$"
            // locale-only [$-411]: map the hex locale id
            if after[end...].first == "-" {
                let hex = after[after.index(after: end)...].prefix { $0 != "]" }
                if let id = Int(hex, radix: 16) { return localeCurrency[id] }
            }
            return nil
        }
        for s in code.unicodeScalars where currencyScalars.contains(s) { return String(s) }
        return nil
    }

    static func number(_ d: Double) -> String {
        if d.isFinite, d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
        return String(d)
    }

    // MARK: - Format-code scanning

    /// Collect format-significant characters from the first (positive) section,
    /// skipping quoted text, [bracketed] sections, and `\`-escaped chars.
    private static func significantTokens(_ code: String) -> String {
        let section = code.split(separator: ";", maxSplits: 1).first.map(String.init) ?? code
        let chars = Array(section)
        var out = ""
        var i = 0
        while i < chars.count {
            switch chars[i] {
            case "\"":
                i += 1
                while i < chars.count, chars[i] != "\"" { i += 1 }
                i += 1
            case "[":
                while i < chars.count, chars[i] != "]" { i += 1 }
                i += 1
            case "\\":
                i += 2
            default:
                out.append(chars[i]); i += 1
            }
        }
        return out
    }

    // MARK: - Date/serial rendering

    /// Excel's 1900-system day 0 is 1899-12-30 (absorbing the leap-year bug).
    private static let epoch1900: Date = {
        var c = DateComponents(); c.year = 1899; c.month = 12; c.day = 30
        return utcCalendar.date(from: c)!
    }()
    private static let epoch1904: Date = {
        var c = DateComponents(); c.year = 1904; c.month = 1; c.day = 1
        return utcCalendar.date(from: c)!
    }()
    private static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private static func isoDate(_ serial: Double, withTime: Bool, date1904: Bool) -> String {
        let epoch = date1904 ? epoch1904 : epoch1900
        let date = epoch.addingTimeInterval(serial * 86400)
        let c = utcCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        guard withTime else { return day }
        return day + String(format: " %02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    private static func isoTime(_ serial: Double) -> String {
        let date = epoch1900.addingTimeInterval(serial * 86400)
        let c = utcCalendar.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
}
