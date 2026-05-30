import Foundation
import Combine
import PythonKit

/// Initialises the embedded CPython runtime and exposes it to the app.
/// Must be set up once at app launch before any Python calls are made.
final class PythonBridge: ObservableObject {

    static let shared = PythonBridge()

    let objectWillChange = PassthroughSubject<Void, Never>()

    private(set) var isReady = false {
        willSet { objectWillChange.send() }
    }

    private(set) var error: String? {
        willSet { objectWillChange.send() }
    }

    private init() {}

    func setup() {
        guard !isReady else { return }

        do {
            try configurePythonRuntime()
            validatePython()
            isReady = true
        } catch let e {
            error = e.localizedDescription
        }
    }

    // MARK: - Private

    private func configurePythonRuntime() throws {
        guard let frameworkPath = Bundle.main.privateFrameworksPath else {
            throw BridgeError.frameworkNotFound
        }

        let pythonHome = "\(frameworkPath)/Python.framework/Versions/3.12"
        let stdlibPath = "\(pythonHome)/lib/python3.12"
        let sitePackages = "\(stdlibPath)/site-packages"

        setenv("PYTHONHOME", pythonHome, 1)
        setenv("PYTHONPATH", "\(stdlibPath):\(sitePackages)", 1)
        setenv("HF_HUB_OFFLINE", "0", 1)

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
