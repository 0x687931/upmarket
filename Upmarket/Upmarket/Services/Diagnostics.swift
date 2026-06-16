import Foundation
import OSLog
import Security

enum AppLog {
    nonisolated static let subsystem = "com.upmarket.app"

    nonisolated static let conversion = Logger(subsystem: subsystem, category: "conversion")
    nonisolated static let launch = Logger(subsystem: subsystem, category: "launch")
    nonisolated static let modelDownload = Logger(subsystem: subsystem, category: "modelDownload")
    nonisolated static let storeKit = Logger(subsystem: subsystem, category: "storeKit")
    nonisolated static let fileAccess = Logger(subsystem: subsystem, category: "fileAccess")
    nonisolated static let featureFlags = Logger(subsystem: subsystem, category: "featureFlags")
    nonisolated static let diagnostics = Logger(subsystem: subsystem, category: "diagnostics")
}

enum AppSignpost {
    nonisolated static let conversion = OSSignposter(logger: AppLog.conversion)
}

enum AppLaunchMetrics {
    private static var startedAt = DispatchTime.now()
    private static var hasStarted = false

    static func reset() {
        startedAt = DispatchTime.now()
        hasStarted = true
        AppLog.launch.info("Launch timing started")
    }

    static func mark(_ phase: String) {
        if !hasStarted {
            reset()
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds &- startedAt.uptimeNanoseconds
        let elapsedMilliseconds = Double(elapsed) / 1_000_000
        AppLog.launch.info(
            "Launch phase \(phase, privacy: .public) at \(String(format: "%.1f", elapsedMilliseconds), privacy: .public)ms"
        )
    }
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
    let lastConversionPipeline: String?
    let lastConversionPathway: String?

    init(
        appVersion: String,
        buildNumber: String,
        macOSVersion: String,
        hardwareModel: String,
        localeIdentifier: String,
        correlationID: String?,
        lastConversionStage: String?,
        lastErrorCode: String?,
        plistStatus: String,
        entitlementStatus: String,
        modelManifestStatus: String,
        lastConversionPipeline: String? = nil,
        lastConversionPathway: String? = nil
    ) {
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.macOSVersion = macOSVersion
        self.hardwareModel = hardwareModel
        self.localeIdentifier = localeIdentifier
        self.correlationID = correlationID
        self.lastConversionStage = lastConversionStage
        self.lastErrorCode = lastErrorCode
        self.plistStatus = plistStatus
        self.entitlementStatus = entitlementStatus
        self.modelManifestStatus = modelManifestStatus
        self.lastConversionPipeline = lastConversionPipeline
        self.lastConversionPathway = lastConversionPathway
    }
}

enum Diagnostics {
    static func makeSnapshot(
        correlationID: String? = nil,
        lastConversionStage: ConversionStage? = nil,
        lastErrorCode: String? = nil,
        lastConversionPipeline: Pipeline? = nil,
        lastConversionPathway: ConversionPathway? = nil,
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
            lastConversionStage: lastConversionStage.map { neutralStageName($0.rawValue) },
            lastErrorCode: lastErrorCode,
            plistStatus: plistStatus(bundle: bundle),
            entitlementStatus: entitlementStatus(),
            modelManifestStatus: modelManifestStatus(modelDirectory: modelDirectory),
            lastConversionPipeline: lastConversionPipeline?.rawValue,
            lastConversionPathway: lastConversionPathway?.rawValue
        )
    }

    static func makeRedactedBundle(snapshot: DiagnosticSnapshot) throws -> Data {
        AppLog.diagnostics.info("Creating redacted diagnostic snapshot")
        return try JSONEncoder().encode(snapshot)
    }

    static func redactPath(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    nonisolated static func neutralStageName(_ stage: String) -> String {
        switch stage {
        case ConversionStage.queued.rawValue:
            return "Queued"
        case ConversionStage.copying.rawValue:
            return "Preparing document"
        case ConversionStage.analysing.rawValue:
            return "Analysing document"
        case ConversionStage.extracting.rawValue:
            return "Reading document"
        case ConversionStage.processing.rawValue:
            return "Processing document"
        case ConversionStage.postProcessing.rawValue:
            return "Cleaning Markdown"
        case ConversionStage.complete.rawValue:
            return "Done"
        case ConversionStage.failed.rawValue:
            return "Failed"
        case ConversionStage.cancelled.rawValue:
            return "Cancelled"
        default:
            return stage
        }
    }

    static func recentLogExport(limit: Int = 200, since seconds: TimeInterval = 900) -> String {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: Date().addingTimeInterval(-seconds))
            let entries = try store.getEntries(at: position)
                .compactMap { $0 as? OSLogEntryLog }
                .filter { $0.subsystem == AppLog.subsystem }
                .suffix(limit)

            guard !entries.isEmpty else { return "No recent Upmarket logs in this process." }
            return entries.map { entry in
                let message = sanitizeLogMessage(entry.composedMessage)
                return "\(entry.date) [\(entry.category)] \(entry.level): \(message)"
            }
            .joined(separator: "\n")
        } catch {
            AppLog.diagnostics.error("Failed to export recent logs: \(error.localizedDescription, privacy: .private)")
            return "Log export unavailable: \(String(describing: type(of: error)))"
        }
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

    private static func sanitizeLogMessage(_ message: String) -> String {
        message
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
            .replacingOccurrences(
                of: #"/Users/[^/\s]+"#,
                with: "/Users/[redacted]",
                options: .regularExpression
            )
    }
}
