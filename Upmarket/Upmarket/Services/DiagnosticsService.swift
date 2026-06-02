import Foundation

final class DiagnosticsService {
    static let shared = DiagnosticsService()

    private init() {}

    func makeSnapshot(
        correlationID: String? = nil,
        lastConversionStage: ConversionStage? = nil,
        lastErrorCode: String? = nil
    ) -> DiagnosticSnapshot {
        Diagnostics.makeSnapshot(
            correlationID: correlationID,
            lastConversionStage: lastConversionStage,
            lastErrorCode: lastErrorCode
        )
    }

    func recentLogExport(limit: Int = 200, since seconds: TimeInterval = 900) -> String {
        Diagnostics.recentLogExport(limit: limit, since: seconds)
    }

    func makeRedactedBundle(snapshot: DiagnosticSnapshot) throws -> Data {
        try Diagnostics.makeRedactedBundle(snapshot: snapshot)
    }

    func redactPath(_ path: String) -> String {
        Diagnostics.redactPath(path)
    }
}
