import Combine
import Foundation
import OSLog
import PythonKit

enum PythonBridgeError: Error, Equatable, LocalizedError, Sendable {
    case frameworkNotFound
    case runtimeUnavailable(String)
    case moduleUnavailable(String)
    case callFailed(String)

    var errorDescription: String? {
        switch self {
        case .frameworkNotFound:
            return "Conversion runtime is missing from the app bundle."
        case .runtimeUnavailable(let message):
            return "Conversion runtime unavailable: \(message)"
        case .moduleUnavailable(let name):
            return "Conversion component unavailable: \(name)"
        case .callFailed(let message):
            return "Conversion component failed: \(message)"
        }
    }

    var diagnosticCode: String {
        switch self {
        case .frameworkNotFound:
            return "runtime.bridge.missing"
        case .runtimeUnavailable:
            return "runtime.bridge.unavailable"
        case .moduleUnavailable:
            return "runtime.bridge.component-unavailable"
        case .callFailed:
            return "runtime.bridge.call-failed"
        }
    }
}

struct PythonRuntimeStatus: Equatable, Sendable {
    let isReady: Bool
    let version: String?
    let error: PythonBridgeError?
}

actor PythonRuntime {
    static let shared = PythonRuntime()

    private var isReady = false
    private var version: String?
    private var lastError: PythonBridgeError?

    func status() -> PythonRuntimeStatus {
        PythonRuntimeStatus(isReady: isReady, version: version, error: lastError)
    }

    func setup() {
        guard !isReady else { return }

        do {
            try configurePythonRuntime()
            let sys = Python.import("sys")
            version = String(sys.version) ?? "unknown"
            isReady = true
            lastError = nil
            AppLog.pythonBridge.info("Conversion runtime ready version=\(self.version ?? "unknown", privacy: .public)")
        } catch let error as PythonBridgeError {
            isReady = false
            lastError = error
            AppLog.pythonBridge.error("Conversion runtime setup failed: \(error.localizedDescription, privacy: .private)")
        } catch {
            isReady = false
            lastError = .runtimeUnavailable(error.localizedDescription)
            AppLog.pythonBridge.error("Conversion runtime setup failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    func setDownloadModeEnabled(_ enabled: Bool) {
        setenv("HF_HUB_OFFLINE", enabled ? "0" : "1", 1)
        setenv("TRANSFORMERS_OFFLINE", enabled ? "0" : "1", 1)
    }

    func withPython<T: Sendable>(_ operation: () throws -> T) async throws -> T {
        if !isReady { setup() }
        guard isReady else {
            throw lastError ?? PythonBridgeError.runtimeUnavailable("Python did not initialise.")
        }

        do {
            return try operation()
        } catch let error as PythonBridgeError {
            throw error
        } catch {
            throw PythonBridgeError.callFailed(error.localizedDescription)
        }
    }

    func withPythonEnvironment<T: Sendable>(
        _ environment: [String: String],
        operation: () throws -> T
    ) async throws -> T {
        if !isReady { setup() }
        guard isReady else {
            throw lastError ?? PythonBridgeError.runtimeUnavailable("Python did not initialise.")
        }

        var previous: [String: String?] = [:]
        for key in environment.keys {
            previous[key] = getenv(key).map { String(cString: $0) }
        }
        for (key, value) in environment {
            setenv(key, value, 1)
        }
        defer {
            for (key, value) in previous {
                if let value {
                    setenv(key, value, 1)
                } else {
                    unsetenv(key)
                }
            }
        }

        do {
            return try operation()
        } catch let error as PythonBridgeError {
            throw error
        } catch {
            throw PythonBridgeError.callFailed(error.localizedDescription)
        }
    }

    func withPythonDownload<T: Sendable>(_ operation: () throws -> T) async throws -> T {
        if !isReady { setup() }
        guard isReady else {
            throw lastError ?? PythonBridgeError.runtimeUnavailable("Python did not initialise.")
        }

        setDownloadModeEnabled(true)
        defer { setDownloadModeEnabled(false) }

        do {
            return try operation()
        } catch let error as PythonBridgeError {
            throw error
        } catch {
            throw PythonBridgeError.callFailed(error.localizedDescription)
        }
    }

    private func configurePythonRuntime() throws {
        guard let frameworkPath = Bundle.main.privateFrameworksPath else {
            throw PythonBridgeError.frameworkNotFound
        }

        let pythonHome = "\(frameworkPath)/Python.framework/Versions/3.12"
        let stdlibPath = "\(pythonHome)/lib/python3.12"
        let sitePackages = "\(stdlibPath)/site-packages"

        setenv("PYTHONHOME", pythonHome, 1)
        setenv("PYTHONPATH", "\(stdlibPath):\(sitePackages)", 1)
        setDownloadModeEnabled(false)

        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Upmarket/models")
            .path
        setenv("UPMARKET_MODELS_DIR", appSupport, 1)
        setenv("HF_HUB_CACHE", appSupport, 1)
    }
}

/// Observable facade for SwiftUI. Python calls must go through PythonRuntime/PythonWorker.
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

    private init() {}

    func setup() {
        Task {
            await PythonRuntime.shared.setup()
            let status = await PythonRuntime.shared.status()
            await MainActor.run {
                self.isReady = status.isReady
                self.version = status.version
                self.error = status.error?.localizedDescription
            }
        }
    }
}
