import Combine
import Foundation
import OSLog

enum PythonBridgeError: Error, Equatable, LocalizedError, Sendable {
    case helperUnavailable(String)
    case helperCrashed(String)
    case helperBadExit(Int32)
    case helperStalled
    case invalidResponse(String)
    case runtimeUnavailable(String)
    case moduleUnavailable(String)
    case callFailed(String)

    var errorDescription: String? {
        switch self {
        case .helperUnavailable:
            return "Conversion engine is unavailable."
        case .helperCrashed, .helperBadExit, .helperStalled:
            return "Conversion engine stopped unexpectedly. Please try again."
        case .invalidResponse:
            return "Conversion engine returned an unreadable result."
        case .runtimeUnavailable:
            return "Conversion engine is unavailable."
        case .moduleUnavailable:
            return "Conversion component is unavailable."
        case .callFailed:
            return "Conversion component failed."
        }
    }

    var diagnosticCode: String {
        switch self {
        case .helperUnavailable:
            return "runtime.helper.unavailable"
        case .helperCrashed:
            return "runtime.helper.crashed"
        case .helperBadExit:
            return "runtime.helper.bad-exit"
        case .helperStalled:
            return "runtime.helper.stalled"
        case .invalidResponse:
            return "runtime.helper.invalid-response"
        case .runtimeUnavailable:
            return "runtime.helper.runtime-unavailable"
        case .moduleUnavailable:
            return "runtime.helper.component-unavailable"
        case .callFailed:
            return "runtime.helper.call-failed"
        }
    }
}

struct PythonRuntimeStatus: Equatable, Sendable {
    let isReady: Bool
    let version: String?
    let error: PythonBridgeError?
}

/// Observable facade for SwiftUI. Runtime calls must go through PythonWorker.
final class PythonBridge: ObservableObject {
    static let shared = PythonBridge()

    let objectWillChange = PassthroughSubject<Void, Never>()

    private(set) var isReady = false {
        willSet { objectWillChange.send() }
    }

    private(set) var error: String? {
        willSet { objectWillChange.send() }
    }

    private(set) var version: String? {
        willSet { objectWillChange.send() }
    }

    private let helperClient = RuntimeHelperClient()

    private init() {}

    func setup() {
        Task.detached(priority: .userInitiated) {
            let status: PythonRuntimeStatus
            do {
                status = try await self.helperClient.readiness()
                AppLog.pythonBridge.info("Runtime helper ready")
            } catch let error as PythonBridgeError {
                status = PythonRuntimeStatus(isReady: false, version: nil, error: error)
                AppLog.pythonBridge.error("Runtime helper setup failed code=\(error.diagnosticCode, privacy: .public)")
            } catch {
                let bridgeError = PythonBridgeError.callFailed(error.localizedDescription)
                status = PythonRuntimeStatus(isReady: false, version: nil, error: bridgeError)
                AppLog.pythonBridge.error("Runtime helper setup failed code=\(bridgeError.diagnosticCode, privacy: .public)")
            }

            await MainActor.run {
                self.isReady = status.isReady
                self.version = status.version
                self.error = status.error?.localizedDescription
            }
        }
    }
}
