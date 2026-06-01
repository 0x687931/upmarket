import Foundation
import OSLog

struct RuntimeHelperClient: Sendable {
    private let executableURL: URL?
    private let livenessInterval: TimeInterval

    nonisolated init(executableURL: URL? = nil, livenessInterval: TimeInterval = 90) {
        self.executableURL = executableURL
        self.livenessInterval = livenessInterval
    }

    nonisolated func readiness() async throws -> PythonRuntimeStatus {
        let response: RuntimeHelperResponse = try await perform(.readiness)
        guard response.success else { throw bridgeError(from: response) }
        return PythonRuntimeStatus(isReady: true, version: response.version, error: nil)
    }

    nonisolated func analyse(fileURL: URL, workspaceURL: URL) async throws -> ComplexityAdvice? {
        let response: RuntimeHelperResponse = try await perform(.analyse(filePath: fileURL.path, workspacePath: workspaceURL.path))
        guard response.success else { throw bridgeError(from: response) }
        guard let advice = response.advice else { return nil }
        return ComplexityAdvice(
            recommendation: ComplexityAdvice.Recommendation(rawValue: advice.recommendation) ?? .basic,
            score: advice.score,
            reasons: advice.reasons,
            detectedLanguage: advice.detectedLanguage
        )
    }

    nonisolated func convert(
        fileURL: URL,
        title: String,
        useAI: Bool,
        password: String?,
        workspaceURL: URL,
        heartbeat: (@Sendable () -> Void)? = nil
    ) async throws -> ConversionResult {
        let response: RuntimeHelperResponse = try await perform(.convert(
            filePath: fileURL.path,
            title: title,
            useAI: useAI,
            password: password,
            workspacePath: workspaceURL.path
        ), heartbeat: heartbeat)
        guard response.success else {
            if response.needsPassword {
                return .failure(ConversionError.passwordRequired.errorDescription ?? "This PDF is password-protected.")
            }
            throw bridgeError(from: response)
        }
        guard let output = response.output else {
            throw PythonBridgeError.invalidResponse("missing output")
        }
        return .success(ConversionOutput(
            markdown: output.markdown,
            pages: output.pages,
            format: output.format,
            title: output.title,
            pipeline: Pipeline(rawValue: output.pipeline) ?? .fast
        ))
    }

    nonisolated func checkModels() async throws -> [ModelStatus] {
        let response: RuntimeHelperResponse = try await perform(.checkModels)
        guard response.success else { throw bridgeError(from: response) }
        return (response.models ?? []).map {
            ModelStatus(
                key: $0.key,
                name: $0.name,
                description: $0.description,
                isDownloaded: $0.isDownloaded,
                sizeMB: $0.sizeMB,
                isRequired: $0.isRequired,
                tier: $0.tier
            )
        }
    }

    nonisolated func setOfflineMode() async {
        _ = try? await perform(.setOfflineMode) as RuntimeHelperResponse
    }

    nonisolated func downloadModel(key: String, progressFile: String, workspaceURL: URL) async -> ModelDownloadResult {
        do {
            let response: RuntimeHelperResponse = try await perform(.downloadModel(
                key: key,
                progressFile: progressFile,
                workspacePath: workspaceURL.path
            ))
            return ModelDownloadResult(success: response.success, error: response.success ? nil : response.message)
        } catch {
            AppLog.modelDownload.error("Model download failed key=\(key, privacy: .public) code=runtime.helper")
            return ModelDownloadResult(success: false, error: "Download failed")
        }
    }

    private nonisolated func perform<T: Decodable>(
        _ request: RuntimeHelperRequest,
        heartbeat: (@Sendable () -> Void)? = nil
    ) async throws -> T {
        let executable = try helperExecutableURL()
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--request-json-stdin"]

        var environment = ProcessInfo.processInfo.environment
        environment["HF_HUB_OFFLINE"] = request.operation == "downloadModel" ? "0" : "1"
        environment["TRANSFORMERS_OFFLINE"] = request.operation == "downloadModel" ? "0" : "1"
        process.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        let state = RuntimeHelperProcessState()
        let decoder = JSONDecoder()
        let recordOutputLine: @Sendable (String) -> Void = { line in
            guard let lineData = line.data(using: .utf8) else { return }
            if let event = try? decoder.decode(RuntimeHelperEvent.self, from: lineData), event.event == "heartbeat" {
                state.markHeartbeat()
                heartbeat?()
            } else {
                state.recordResponseLine(line)
            }
        }

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            state.append(data)
            for line in state.drainLines() {
                recordOutputLine(line)
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            AppLog.pythonBridge.debug("Runtime helper stderr drained bytes=\(data.count, privacy: .public)")
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                do {
                    try process.run()
                    let requestData = try JSONEncoder().encode(request)
                    stdin.fileHandleForWriting.write(requestData)
                    stdin.fileHandleForWriting.closeFile()
                } catch {
                    continuation.resume(throwing: PythonBridgeError.helperUnavailable(error.localizedDescription))
                    return
                }

                let monitor = RuntimeHelperLivenessMonitor(
                    process: process,
                    interval: livenessInterval,
                    state: state
                ) {
                    process.terminate()
                    continuation.resume(throwing: PythonBridgeError.helperStalled)
                }
                monitor.start()

                process.terminationHandler = { terminated in
                    stdout.fileHandleForReading.readabilityHandler = nil
                    let remainingOutput = stdout.fileHandleForReading.readDataToEndOfFile()
                    if !remainingOutput.isEmpty {
                        state.append(remainingOutput)
                    }
                    for line in state.drainLines() {
                        recordOutputLine(line)
                    }
                    if let line = state.drainRemainingLine() {
                        recordOutputLine(line)
                    }
                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    monitor.cancel()

                    if state.wasResumed {
                        return
                    }
                    state.markResumed()

                    if terminated.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: PythonBridgeError.helperCrashed("signal \(terminated.terminationStatus)"))
                        return
                    }

                    guard terminated.terminationStatus == 0 else {
                        continuation.resume(throwing: PythonBridgeError.helperBadExit(terminated.terminationStatus))
                        return
                    }

                    guard let line = state.responseLine,
                          let data = line.data(using: .utf8) else {
                        continuation.resume(throwing: PythonBridgeError.invalidResponse("empty response"))
                        return
                    }

                    do {
                        continuation.resume(returning: try decoder.decode(T.self, from: data))
                    } catch {
                        continuation.resume(throwing: PythonBridgeError.invalidResponse(error.localizedDescription))
                    }
                }
            }
        } onCancel: {
            process.terminate()
        }
    }

    private nonisolated func helperExecutableURL() throws -> URL {
        if let executableURL {
            return executableURL
        }
        guard let url = Bundle.main.url(forAuxiliaryExecutable: "UpmarketRuntimeHelper") else {
            throw PythonBridgeError.helperUnavailable("missing helper executable")
        }
        return url
    }

    private nonisolated func bridgeError(from response: RuntimeHelperResponse) -> PythonBridgeError {
        switch response.code {
        case "runtime.helper.runtime-unavailable":
            return .runtimeUnavailable(response.message ?? "unavailable")
        case "runtime.helper.component-unavailable":
            return .moduleUnavailable(response.message ?? "component")
        case "runtime.helper.invalid-response":
            return .invalidResponse(response.message ?? "invalid")
        default:
            return .callFailed(response.message ?? "failed")
        }
    }
}

struct RuntimeHelperRequest: Codable, Sendable {
    let operation: String
    let filePath: String?
    let title: String?
    let useAI: Bool?
    let password: String?
    let workspacePath: String?
    let key: String?
    let progressFile: String?

    static let readiness = RuntimeHelperRequest(operation: "readiness", filePath: nil, title: nil, useAI: nil, password: nil, workspacePath: nil, key: nil, progressFile: nil)
    static let checkModels = RuntimeHelperRequest(operation: "checkModels", filePath: nil, title: nil, useAI: nil, password: nil, workspacePath: nil, key: nil, progressFile: nil)
    static let setOfflineMode = RuntimeHelperRequest(operation: "setOfflineMode", filePath: nil, title: nil, useAI: nil, password: nil, workspacePath: nil, key: nil, progressFile: nil)

    static func analyse(filePath: String, workspacePath: String) -> RuntimeHelperRequest {
        RuntimeHelperRequest(operation: "analyse", filePath: filePath, title: nil, useAI: nil, password: nil, workspacePath: workspacePath, key: nil, progressFile: nil)
    }

    static func convert(filePath: String, title: String, useAI: Bool, password: String?, workspacePath: String) -> RuntimeHelperRequest {
        RuntimeHelperRequest(operation: "convert", filePath: filePath, title: title, useAI: useAI, password: password, workspacePath: workspacePath, key: nil, progressFile: nil)
    }

    static func downloadModel(key: String, progressFile: String, workspacePath: String) -> RuntimeHelperRequest {
        RuntimeHelperRequest(operation: "downloadModel", filePath: nil, title: nil, useAI: nil, password: nil, workspacePath: workspacePath, key: key, progressFile: progressFile)
    }
}

struct RuntimeHelperResponse: Codable, Sendable {
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

struct RuntimeAdviceDTO: Codable, Sendable {
    let recommendation: String
    let score: Int
    let reasons: [String]
    let detectedLanguage: String?
}

struct RuntimeConversionOutputDTO: Codable, Sendable {
    let markdown: String
    let pages: Int
    let format: String
    let title: String
    let pipeline: String
}

struct RuntimeModelStatusDTO: Codable, Sendable {
    let key: String
    let name: String
    let description: String
    let isDownloaded: Bool
    let sizeMB: Int
    let isRequired: Bool
    let tier: String
}

private struct RuntimeHelperEvent: Codable {
    let event: String
}

private final class RuntimeHelperProcessState: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var lines: [String] = []
    private var resumed = false
    private var heartbeat = Date()

    var responseLine: String? {
        lock.lock()
        defer { lock.unlock() }
        return lines.last
    }

    var lastHeartbeat: Date {
        lock.lock()
        defer { lock.unlock() }
        return heartbeat
    }

    var wasResumed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return resumed
    }

    func markResumed() {
        lock.lock()
        resumed = true
        lock.unlock()
    }

    func append(_ data: Data) {
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }

    func drainLines() -> [String] {
        lock.lock()
        defer { lock.unlock() }

        var drained: [String] = []
        while let range = buffer.firstRange(of: Data([0x0A])) {
            let lineData = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0...range.lowerBound)
            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                drained.append(line)
            }
        }
        return drained
    }

    func drainRemainingLine() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !buffer.isEmpty else { return nil }
        defer { buffer.removeAll() }
        return String(data: buffer, encoding: .utf8)
    }

    func recordResponseLine(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    func markHeartbeat() {
        lock.lock()
        heartbeat = Date()
        lock.unlock()
    }
}

private final class RuntimeHelperLivenessMonitor: @unchecked Sendable {
    private let queue = DispatchQueue(label: "UpmarketRuntimeHelperLiveness")
    private let interval: TimeInterval
    private let state: RuntimeHelperProcessState
    private weak var process: Process?
    private let onStalled: () -> Void
    private var timer: DispatchSourceTimer?

    init(process: Process, interval: TimeInterval, state: RuntimeHelperProcessState, onStalled: @escaping () -> Void) {
        self.process = process
        self.interval = interval
        self.state = state
        self.onStalled = onStalled
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval / 2)
        timer.setEventHandler { [weak self] in
            guard let self, self.process?.isRunning == true else { return }
            if Date().timeIntervalSince(self.state.lastHeartbeat) >= self.interval, !self.state.wasResumed {
                self.state.markResumed()
                self.onStalled()
            }
        }
        self.timer = timer
        timer.resume()
    }

    func cancel() {
        timer?.cancel()
        timer = nil
    }
}
