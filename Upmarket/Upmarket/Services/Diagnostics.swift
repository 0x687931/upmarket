import Foundation
import OSLog
import Security

enum AppLog {
    private static let subsystem = "com.upmarket.app"

    nonisolated static let conversion = Logger(subsystem: subsystem, category: "conversion")
    nonisolated static let pythonBridge = Logger(subsystem: subsystem, category: "pythonBridge")
    nonisolated static let modelDownload = Logger(subsystem: subsystem, category: "modelDownload")
    nonisolated static let storeKit = Logger(subsystem: subsystem, category: "storeKit")
    nonisolated static let fileAccess = Logger(subsystem: subsystem, category: "fileAccess")
    nonisolated static let featureFlags = Logger(subsystem: subsystem, category: "featureFlags")
    nonisolated static let diagnostics = Logger(subsystem: subsystem, category: "diagnostics")
}

struct DiagnosticSnapshot: Codable, Equatable {
    let appVersion: String
    let buildNumber: String
    let macOSVersion: String
    let hardwareModel: String
    let localeIdentifier: String
    let correlationID: String?
    let lastConversionStage: String?
    let lastErrorCode: String?
    let plistStatus: String
    let entitlementStatus: String
    let modelManifestStatus: String
}

enum Diagnostics {
    static func makeSnapshot(
        correlationID: String? = nil,
        lastConversionStage: ConversionStage? = nil,
        lastErrorCode: String? = nil,
        bundle: Bundle = .main,
        modelDirectory: URL? = nil
    ) -> DiagnosticSnapshot {
        DiagnosticSnapshot(
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            hardwareModel: hardwareModel(),
            localeIdentifier: Locale.current.identifier,
            correlationID: correlationID,
            lastConversionStage: lastConversionStage?.rawValue,
            lastErrorCode: lastErrorCode,
            plistStatus: plistStatus(bundle: bundle),
            entitlementStatus: entitlementStatus(),
            modelManifestStatus: modelManifestStatus(modelDirectory: modelDirectory)
        )
    }

    static func makeRedactedBundle(snapshot: DiagnosticSnapshot) throws -> Data {
        AppLog.diagnostics.info("Creating redacted diagnostic snapshot")
        return try JSONEncoder().encode(snapshot)
    }

    static func redactPath(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    private static func plistStatus(bundle: Bundle) -> String {
        let hasURLTypes = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") != nil
        let hasServices = bundle.object(forInfoDictionaryKey: "NSServices") != nil
        let hasSpeech = bundle.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") != nil
        return hasURLTypes && hasServices && hasSpeech ? "ok" : "missing-required-keys"
    }

    private static func entitlementStatus() -> String {
        guard let task = SecTaskCreateFromSelf(nil) else { return "unknown" }
        guard let value = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.security.app-sandbox" as CFString,
            nil
        ) else { return "unknown" }
        return (value as? Bool) == true ? "sandboxed" : "not-sandboxed"
    }

    private static func modelManifestStatus(modelDirectory: URL?) -> String {
        let directory = modelDirectory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Upmarket/models", isDirectory: true)
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return "not-installed" }

        let modelDirectories = children.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        guard !modelDirectories.isEmpty else { return "not-installed" }
        let missingManifest = modelDirectories.contains {
            !FileManager.default.fileExists(atPath: $0.appendingPathComponent("manifest.json").path)
        }
        return missingManifest ? "missing-manifest" : "manifest-present"
    }

    private static func hardwareModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(String(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? "unknown" : identifier
    }
}
