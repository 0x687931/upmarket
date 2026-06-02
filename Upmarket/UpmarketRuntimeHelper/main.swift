import Foundation
import Darwin
import PythonKit

struct RuntimeHelperRequest: Codable {
    let operation: String
    let filePath: String?
    let title: String?
    let useAI: Bool?
    let password: String?
    let workspacePath: String?
    let key: String?
    let progressFile: String?
}

struct RuntimeHelperResponse: Codable {
    let success: Bool
    let code: String?
    let message: String?
    let version: String?
    let needsPassword: Bool
    let advice: RuntimeAdviceDTO?
    let output: RuntimeConversionOutputDTO?
    let models: [RuntimeModelStatusDTO]?

    init(success: Bool, code: String? = nil, message: String? = nil, version: String? = nil, needsPassword: Bool = false, advice: RuntimeAdviceDTO? = nil, output: RuntimeConversionOutputDTO? = nil, models: [RuntimeModelStatusDTO]? = nil) {
        self.success = success
        self.code = code
        self.message = message
        self.version = version
        self.needsPassword = needsPassword
        self.advice = advice
        self.output = output
        self.models = models
    }
}

struct RuntimeAdviceDTO: Codable {
    let recommendation: String
    let score: Int
    let reasons: [String]
    let detectedLanguage: String?
}

struct RuntimeConversionOutputDTO: Codable {
    let markdown: String
    let pages: Int
    let format: String
    let title: String
    let pipeline: String
}

struct RuntimeModelStatusDTO: Codable {
    let key: String
    let name: String
    let description: String
    let isDownloaded: Bool
    let sizeMB: Int
    let isRequired: Bool
    let tier: String
}

struct UpmarketRuntimeHelper {
    static func run() {
        abortIfPrivilegedProcess()
        let heartbeat = Heartbeat()
        heartbeat.start()

        do {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            let request = try JSONDecoder().decode(RuntimeHelperRequest.self, from: data)
            configureRuntime(workspacePath: request.workspacePath)
            installPythonSandbox()
            let response = try handle(request)
            heartbeat.stop()
            emit(response)
        } catch let error as HelperError {
            heartbeat.stop()
            emit(RuntimeHelperResponse(success: false, code: error.code, message: error.neutralMessage))
        } catch {
            heartbeat.stop()
            emit(RuntimeHelperResponse(success: false, code: "runtime.helper.call-failed", message: "operation failed"))
        }
    }

    private static func handle(_ request: RuntimeHelperRequest) throws -> RuntimeHelperResponse {
        switch request.operation {
        case "readiness":
            let sys = Python.import("sys")
            _ = Python.import("docling_bridge.converter")
            return RuntimeHelperResponse(success: true, version: String(sys.version) ?? "unknown")
        case "analyse":
            guard let filePath = request.filePath else { throw HelperError.invalidRequest }
            let analyser = Python.import("docling_bridge.analyser")
            let pyResult = analyser.analyse(filePath)
            let success = Bool(pyResult["success"]) ?? false
            guard success else { return RuntimeHelperResponse(success: true) }

            var reasons: [String] = []
            for item in pyResult["reasons"] {
                if let reason = String(item) { reasons.append(reason) }
            }
            let detectedLanguage = String(pyResult["signals"]["detected_language"]) ?? nil
            return RuntimeHelperResponse(success: true, advice: RuntimeAdviceDTO(
                recommendation: String(pyResult["recommendation"]) ?? "basic",
                score: Int(pyResult["score"]) ?? 0,
                reasons: reasons,
                detectedLanguage: detectedLanguage == "None" ? nil : detectedLanguage
            ))
        case "convert":
            guard let filePath = request.filePath,
                  let title = request.title else { throw HelperError.invalidRequest }
            let converter = Python.import("docling_bridge.converter")
            var options: [String: PythonObject] = [
                "use_ai": PythonObject(request.useAI ?? false),
                "use_enhanced": PythonObject(true),
                "ocr": PythonObject(true)
            ]
            if let password = request.password {
                options["password"] = PythonObject(password)
            }
            let pyResult = converter.convert(filePath, PythonObject(options))
            if Bool(pyResult["needs_password"]) ?? false {
                return RuntimeHelperResponse(success: false, code: "conversion.password", message: "password required", needsPassword: true)
            }
            let success = Bool(pyResult["success"]) ?? false
            guard success else {
                return RuntimeHelperResponse(success: false, code: "runtime.helper.call-failed", message: "conversion failed")
            }
            let meta = pyResult["metadata"]
            return RuntimeHelperResponse(success: true, output: RuntimeConversionOutputDTO(
                markdown: String(pyResult["markdown"]) ?? "",
                pages: Int(meta["pages"]) ?? 0,
                format: String(meta["format"]) ?? "",
                title: title,
                pipeline: String(pyResult["pipeline"]) ?? "fast"
            ))
        case "checkModels":
            let manager = Python.import("upmarket_models.model_manager")
            let pyStatus = manager.check_models()
            var models: [RuntimeModelStatusDTO] = []
            for item in pyStatus.items() {
                guard let key = String(item[0]) else { continue }
                let info = item[1]
                models.append(RuntimeModelStatusDTO(
                    key: key,
                    name: String(info["name"]) ?? key,
                    description: String(info["description"]) ?? "",
                    isDownloaded: Bool(info["downloaded"]) ?? false,
                    sizeMB: Int(info["size_mb"]) ?? 0,
                    isRequired: Bool(info["required"]) ?? false,
                    tier: String(info["tier"]) ?? "basic"
                ))
            }
            return RuntimeHelperResponse(success: true, models: models.sorted { $0.isRequired && !$1.isRequired })
        case "setOfflineMode":
            setenv("HF_HUB_OFFLINE", "1", 1)
            setenv("TRANSFORMERS_OFFLINE", "1", 1)
            let manager = Python.import("upmarket_models.model_manager")
            manager.set_offline_mode()
            return RuntimeHelperResponse(success: true)
        case "downloadModel":
            guard let key = request.key,
                  let progressFile = request.progressFile else { throw HelperError.invalidRequest }
            setenv("HF_HUB_OFFLINE", "0", 1)
            setenv("TRANSFORMERS_OFFLINE", "0", 1)
            let manager = Python.import("upmarket_models.model_manager")
            let result = manager.download_model(key, progressFile)
            let success = Bool(result["success"]) ?? false
            return RuntimeHelperResponse(
                success: success,
                code: success ? nil : "runtime.helper.call-failed",
                message: success ? nil : "download failed"
            )
        default:
            throw HelperError.invalidRequest
        }
    }

    private static func configureRuntime(workspacePath: String?) {
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let frameworkRoot = executableURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Frameworks/Python.framework/Versions/3.12", isDirectory: true)
        let stdlibPath = frameworkRoot.appendingPathComponent("lib/python3.12", isDirectory: true)
        let sitePackagesPath = stdlibPath.appendingPathComponent("site-packages", isDirectory: true)

        setenv("PYTHONHOME", frameworkRoot.path, 1)
        setenv("PYTHONPATH", "\(stdlibPath.path):\(sitePackagesPath.path)", 1)
        setenv("HF_HUB_OFFLINE", getenv("HF_HUB_OFFLINE").map { String(cString: $0) } ?? "1", 1)
        setenv("TRANSFORMERS_OFFLINE", getenv("TRANSFORMERS_OFFLINE").map { String(cString: $0) } ?? "1", 1)
        setenv("UPMARKET_RUNTIME_SANDBOX", "1", 1)

        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Upmarket/models", isDirectory: true)
            .path
        setenv("UPMARKET_MODELS_DIR", appSupport, 1)
        setenv("HF_HUB_CACHE", appSupport, 1)

        if let workspacePath {
            setenv("TMPDIR", workspacePath, 1)
            setenv("UPMARKET_ALLOWED_INPUT_ROOTS", workspacePath, 1)
        }
    }

    private static func abortIfPrivilegedProcess() {
        let realUserID = getuid()
        let effectiveUserID = geteuid()
        let realGroupID = getgid()
        let effectiveGroupID = getegid()
        guard realUserID != 0,
              effectiveUserID != 0,
              realUserID == effectiveUserID,
              realGroupID == effectiveGroupID else {
            FileHandle.standardError.write(Data("UpmarketRuntimeHelper refuses to run with elevated privileges.\n".utf8))
            _exit(77)
        }
    }

    private static func installPythonSandbox() {
        let security = Python.import("docling_bridge.security")
        security.install_runtime_sandbox()
    }

    private static func emit(_ response: RuntimeHelperResponse) {
        let data = (try? JSONEncoder().encode(response)) ?? Data(#"{"success":false,"code":"runtime.helper.invalid-response","message":"invalid response","needsPassword":false}"#.utf8)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

enum HelperError: Error {
    case invalidRequest

    var code: String {
        switch self {
        case .invalidRequest:
            return "runtime.helper.invalid-response"
        }
    }

    var neutralMessage: String {
        switch self {
        case .invalidRequest:
            return "invalid request"
        }
    }
}

final class Heartbeat {
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "UpmarketRuntimeHelperHeartbeat")

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 2)
        timer.setEventHandler {
            FileHandle.standardOutput.write(Data(#"{"event":"heartbeat"}"#.utf8))
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        queue.sync {}
    }
}

UpmarketRuntimeHelper.run()
