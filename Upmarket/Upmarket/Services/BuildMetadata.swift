import Foundation

enum BuildMetadata {
    private static let values: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "BuildMetadata", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let values = plist as? [String: Any]
        else {
            return [:]
        }
        return values
    }()

    static var gitCommit: String? {
        cleanString(values["GitCommit"])
    }

    static var gitFullCommit: String? {
        cleanString(values["GitFullCommit"])
    }

    static var isGitDirty: Bool {
        values["GitDirty"] as? Bool ?? false
    }

    static var displayCommit: String? {
        guard let gitCommit else { return nil }
        return isGitDirty ? "\(gitCommit)+dirty" : gitCommit
    }

    static var shouldShowCommitInAbout: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    private static func cleanString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "unknown" else { return nil }
        return trimmed
    }
}
