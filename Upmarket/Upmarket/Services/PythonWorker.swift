import Foundation
import OSLog

struct ModelDownloadResult: Sendable {
    let success: Bool
    let error: String?
}

struct PythonWorker {
    private let helperClient: RuntimeHelperClient

    nonisolated init(helperClient: RuntimeHelperClient = RuntimeHelperClient()) {
        self.helperClient = helperClient
    }

    nonisolated func analyse(fileURL: URL, workspaceURL: URL? = nil) async throws -> ComplexityAdvice? {
        let workspace = try workspaceURL ?? AppWorkspace.create(prefix: "analyse-runtime")
        defer {
            if workspaceURL == nil {
                AppWorkspace.remove(workspace)
            }
        }
        return try await helperClient.analyse(fileURL: fileURL, workspaceURL: workspace)
    }

    nonisolated func convert(
        fileURL: URL,
        title: String,
        useAI: Bool,
        password: String?,
        workspaceURL: URL? = nil,
        heartbeat: (@Sendable () -> Void)? = nil
    ) async -> ConversionResult {
        let workspace: URL
        do {
            workspace = try workspaceURL ?? AppWorkspace.create(prefix: "conversion-runtime")
        } catch {
            AppLog.pythonBridge.error("Advanced conversion failed code=runtime.workspace")
            return .failure(ConversionError.inaccessible.errorDescription ?? "Upmarket couldn't access this file.")
        }
        defer {
            if workspaceURL == nil {
                AppWorkspace.remove(workspace)
            }
        }

        do {
            AppLog.pythonBridge.info("Advanced conversion started ext=\(fileURL.pathExtension, privacy: .public) useAI=\(useAI, privacy: .public)")
            return try await helperClient.convert(
                fileURL: fileURL,
                title: title,
                useAI: useAI,
                password: password,
                workspaceURL: workspace,
                heartbeat: heartbeat
            )
        } catch let error as PythonBridgeError {
            AppLog.pythonBridge.error("Advanced conversion failed code=\(error.diagnosticCode, privacy: .public)")
            return .failure(ConversionError.pythonRuntime(error.localizedDescription).errorDescription ?? "Conversion failed.")
        } catch {
            AppLog.pythonBridge.error("Advanced conversion failed code=runtime.helper")
            return .failure(ConversionError.pythonRuntime(error.localizedDescription).errorDescription ?? "Conversion failed.")
        }
    }

    nonisolated func checkModels() async throws -> [ModelStatus] {
        try await helperClient.checkModels()
    }

    nonisolated func setOfflineMode() async {
        await helperClient.setOfflineMode()
    }

    nonisolated func downloadModel(key: String, progressFile: String) async -> ModelDownloadResult {
        let workspaceURL = URL(fileURLWithPath: progressFile).deletingLastPathComponent()
        return await helperClient.downloadModel(key: key, progressFile: progressFile, workspaceURL: workspaceURL)
    }
}
