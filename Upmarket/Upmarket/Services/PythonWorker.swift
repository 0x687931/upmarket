import Foundation
import PythonKit

struct ModelDownloadResult: Sendable {
    let success: Bool
    let error: String?
}

struct PythonWorker {
    nonisolated init() {}

    nonisolated func analyse(fileURL: URL, workspaceURL: URL? = nil) async throws -> ComplexityAdvice? {
        try await withWorkspace(workspaceURL) {
            let analyser = Python.import("docling_bridge.analyser")
            let pyResult = analyser.analyse(fileURL.path)

            let success = Bool(pyResult["success"]) ?? false
            guard success else { return nil }

            let recommendation = String(pyResult["recommendation"]) ?? "basic"
            let score = Int(pyResult["score"]) ?? 0
            var reasons: [String] = []
            for item in pyResult["reasons"] {
                if let reason = String(item) { reasons.append(reason) }
            }

            let detectedLanguage = String(pyResult["signals"]["detected_language"]) ?? nil
            return ComplexityAdvice(
                recommendation: ComplexityAdvice.Recommendation(rawValue: recommendation) ?? .basic,
                score: score,
                reasons: reasons,
                detectedLanguage: detectedLanguage == "None" ? nil : detectedLanguage
            )
        }
    }

    nonisolated func convert(fileURL: URL, title: String, useAI: Bool, password: String?, workspaceURL: URL? = nil) async -> ConversionResult {
        do {
            return try await withWorkspace(workspaceURL) {
                let converter = Python.import("docling_bridge.converter")
                var opts: [String: PythonObject] = [
                    "use_ai": PythonObject(useAI),
                    "use_enhanced": PythonObject(true),
                    "ocr": PythonObject(true)
                ]
                if let password { opts["password"] = PythonObject(password) }

                let pyResult = converter.convert(fileURL.path, PythonObject(opts))
                let needsPassword = Bool(pyResult["needs_password"]) ?? false
                if needsPassword {
                    return .failure(ConversionError.passwordRequired.errorDescription ?? "This PDF is password-protected.")
                }

                return parseConversionResult(pyResult, title: title)
            }
        } catch let error as PythonBridgeError {
            return .failure(error.localizedDescription)
        } catch {
            return .failure(ConversionError.pythonRuntime(error.localizedDescription).errorDescription ?? error.localizedDescription)
        }
    }

    nonisolated func checkModels() async throws -> [ModelStatus] {
        try await PythonRuntime.shared.withPython {
            let manager = Python.import("upmarket_models.model_manager")
            let pyStatus = manager.check_models()

            var result: [ModelStatus] = []
            for item in pyStatus.items() {
                guard let key = String(item[0]) else { continue }
                let info = item[1]
                result.append(ModelStatus(
                    key: key,
                    name: String(info["name"]) ?? key,
                    description: String(info["description"]) ?? "",
                    isDownloaded: Bool(info["downloaded"]) ?? false,
                    sizeMB: Int(info["size_mb"]) ?? 0,
                    isRequired: Bool(info["required"]) ?? false,
                    tier: String(info["tier"]) ?? "basic"
                ))
            }
            return result.sorted { $0.isRequired && !$1.isRequired }
        }
    }

    nonisolated func setOfflineMode() async {
        await PythonRuntime.shared.setDownloadModeEnabled(false)
        _ = try? await PythonRuntime.shared.withPython {
            let manager = Python.import("upmarket_models.model_manager")
            manager.set_offline_mode()
        }
    }

    nonisolated func downloadModel(key: String, progressFile: String) async -> ModelDownloadResult {
        do {
            return try await PythonRuntime.shared.withPythonDownload {
                let manager = Python.import("upmarket_models.model_manager")
                let result = manager.download_model(key, progressFile)
                let success = Bool(result["success"]) ?? false
                let error = success ? nil : String(result["error"]) ?? "Download failed"
                return ModelDownloadResult(success: success, error: error)
            }
        } catch {
            return ModelDownloadResult(success: false, error: error.localizedDescription)
        }
    }

    private nonisolated func parseConversionResult(_ pyResult: PythonObject, title: String) -> ConversionResult {
        let success = Bool(pyResult["success"]) ?? false
        if success {
            let markdown = String(pyResult["markdown"]) ?? ""
            let meta = pyResult["metadata"]
            let pages = Int(meta["pages"]) ?? 0
            let format = String(meta["format"]) ?? ""
            let pipelineStr = String(pyResult["pipeline"]) ?? "fast"
            let pipeline = Pipeline(rawValue: pipelineStr) ?? .fast
            return .success(ConversionOutput(
                markdown: markdown,
                pages: pages,
                format: format,
                title: title,
                pipeline: pipeline
            ))
        }

        return .failure(String(pyResult["error"]) ?? "Upmarket couldn't convert this document.")
    }

    private nonisolated func withWorkspace<T: Sendable>(
        _ workspaceURL: URL?,
        operation: () throws -> T
    ) async throws -> T {
        guard let workspaceURL else {
            return try await PythonRuntime.shared.withPython(operation)
        }

        return try await PythonRuntime.shared.withPythonEnvironment([
            "TMPDIR": workspaceURL.path,
            "UPMARKET_ALLOWED_INPUT_ROOTS": workspaceURL.path
        ], operation: operation)
    }
}
