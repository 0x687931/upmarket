import Foundation
import PythonKit

/// Initialises the embedded CPython runtime and exposes it to the app.
/// Must be set up once at app launch before any Python calls are made.
@MainActor
final class PythonBridge: ObservableObject {

    static let shared = PythonBridge()

    @Published var isReady = false
    @Published var error: String?

    private init() {}

    func setup() {
        guard !isReady else { return }

        do {
            try configurePythonRuntime()
            validatePython()
            isReady = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Private

    private func configurePythonRuntime() throws {
        guard let frameworkPath = Bundle.main.privateFrameworksPath else {
            throw BridgeError.frameworkNotFound
        }

        let pythonHome = "\(frameworkPath)/Python.framework/Versions/3.12"
        let stdlibPath  = "\(pythonHome)/lib/python3.12"

        setenv("PYTHONHOME", pythonHome, 1)
        setenv("PYTHONPATH", stdlibPath, 1)

        // After models are downloaded, prevents any further HuggingFace hub calls
        setenv("HF_HUB_OFFLINE", "0", 1)

        // Point HF cache to Application Support so models survive app updates
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Upmarket/models")
            .path
        setenv("HF_HUB_CACHE", appSupport, 1)
    }

    private func validatePython() {
        let sys = Python.import("sys")
        let version = String(sys.version) ?? "unknown"
        print("[PythonBridge] Python \(version) ready")
    }
}

enum BridgeError: LocalizedError {
    case frameworkNotFound

    var errorDescription: String? {
        switch self {
        case .frameworkNotFound:
            return "Python.framework not found in app bundle."
        }
    }
}
