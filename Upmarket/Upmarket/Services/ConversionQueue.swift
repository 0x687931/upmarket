import Combine
import Foundation
import OSLog

@MainActor
final class ConversionQueue: ObservableObject {
    typealias RunHandler = (ConversionJob, ConversionRunner.ProgressHandler?) async -> ConversionResult
    typealias AnalyseHandler = (URL) async -> ComplexityAdvice?

    static let shared = ConversionQueue()

    @Published private(set) var jobs: [ConversionJob] = []
    @Published private(set) var isAnalysing = false
    @Published private(set) var complexityAdvice: ComplexityAdvice?
    @Published private(set) var needsPassword = false
    @Published private(set) var latestResult: ConversionResult?

    private let runHandler: RunHandler
    private let analyseHandler: AnalyseHandler
    private var pendingJobIDs: [UUID] = []
    private var pendingHeadIndex = 0
    private var activeJobID: UUID?
    private var activeTask: Task<Void, Never>?
    private var livenessTask: Task<Void, Never>?
    private var continuations: [UUID: CheckedContinuation<ConversionResult, Never>] = [:]
    private var cancelledJobIDs: Set<UUID> = []
    private var lastFailedJobContext: DiagnosticJobContext?
    private let livenessThreshold: TimeInterval = 60

    var isConverting: Bool {
        jobs.contains { $0.isRunning }
    }

    func stalledJobs(referenceDate: Date = Date(), threshold: TimeInterval = 60) -> [ConversionJob] {
        jobs.filter { $0.isStalled || $0.hasNoRecentProgress(referenceDate: referenceDate, threshold: threshold) }
    }

    func job(id: UUID) -> ConversionJob? {
        jobs.first { $0.id == id }
    }

    var lastFailedJob: ConversionJob? {
        jobs.first { job in
            job.stage == .failed && job.result?.errorMessage != nil
        }
    }

    func diagnosticSnapshotForLastFailedJob() -> DiagnosticSnapshot {
        guard let context = lastFailedJobContext else {
            return DiagnosticsService.shared.makeSnapshot()
        }
        return DiagnosticsService.shared.makeSnapshot(
            correlationID: context.correlationID,
            lastConversionStage: context.stage,
            lastErrorCode: context.errorCode
        )
    }

    init(runner: ConversionRunner = ConversionRunner()) {
        self.runHandler = runner.run
        self.analyseHandler = runner.analyse
    }

    init(
        runHandler: @escaping RunHandler,
        analyseHandler: @escaping AnalyseHandler = { _ in nil }
    ) {
        self.runHandler = runHandler
        self.analyseHandler = analyseHandler
    }

    func reset() {
        latestResult = nil
        complexityAdvice = nil
        needsPassword = false
    }

    func analyse(fileURL: URL, completion: @escaping (ComplexityAdvice?) -> Void) {
        isAnalysing = true
        Task {
            let advice = await analyseHandler(fileURL)
            self.isAnalysing = false
            self.complexityAdvice = advice
            completion(advice)
        }
    }

    @discardableResult
    func add(_ url: URL, useAI: Bool = false, password: String? = nil) -> UUID {
        let job = ConversionJob(sourceURL: url, useAI: useAI, password: password)
        jobs.insert(job, at: 0)
        latestResult = nil
        AppLog.conversion.info("Queued conversion correlationID=\(job.correlationID, privacy: .public) ext=\(job.ext, privacy: .public)")
        startLivenessMonitorIfNeeded()
        enqueue(job.id)
        return job.id
    }

    @discardableResult
    func addRejected(_ url: URL, message: String) -> UUID {
        let result = ConversionResult.failure(message)
        let job = ConversionJob(sourceURL: url, stage: .failed, result: result)
        jobs.insert(job, at: 0)
        latestResult = result
        lastFailedJobContext = DiagnosticJobContext(
            correlationID: job.correlationID,
            stage: .failed,
            errorCode: result.diagnosticCode
        )
        AppLog.conversion.warning("Rejected conversion correlationID=\(job.correlationID, privacy: .public) ext=\(job.ext, privacy: .public)")
        return job.id
    }

    func convert(_ url: URL, useAI: Bool = false, password: String? = nil) async -> ConversionResult {
        await withCheckedContinuation { continuation in
            let id = add(url, useAI: useAI, password: password)
            continuations[id] = continuation
        }
    }

    func cancel(_ id: UUID) {
        cancelledJobIDs.insert(id)
        AppLog.conversion.info("Cancelling conversion correlationID=\(id.uuidString, privacy: .public)")
        if activeJobID == id {
            activeTask?.cancel()
        } else {
            pendingJobIDs = pendingJobIDs[pendingHeadIndex...].filter { $0 != id }
            pendingHeadIndex = 0
        }
        finish(id, result: .failure(ConversionError.cancelled.errorDescription ?? "Conversion cancelled."), stage: .cancelled)
    }

    func cancelAll() {
        let ids = jobs.filter(\.isRunning).map(\.id)
        guard !ids.isEmpty else {
            reset()
            return
        }
        cancelledJobIDs.formUnion(ids)
        pendingJobIDs.removeAll(keepingCapacity: true)
        pendingHeadIndex = 0
        activeTask?.cancel()
        for id in ids {
            finish(id, result: .failure(ConversionError.cancelled.errorDescription ?? "Conversion cancelled."), stage: .cancelled)
        }
        reset()
    }

    func handleMemoryPressureCritical() {
        let ids = jobs.filter(\.isRunning).map(\.id)
        guard !ids.isEmpty else { return }
        AppLog.diagnostics.error("Critical memory pressure; stopping active conversions count=\(ids.count, privacy: .public)")
        cancelledJobIDs.formUnion(ids)
        pendingJobIDs.removeAll(keepingCapacity: true)
        pendingHeadIndex = 0
        activeTask?.cancel()
        for id in ids {
            finish(
                id,
                result: .failure(ConversionError.memoryPressure.errorDescription ?? "Conversion paused because this Mac is low on memory."),
                stage: .failed
            )
        }
    }

    @discardableResult
    func retry(_ id: UUID, useAI: Bool? = nil) -> UUID? {
        guard let job = jobs.first(where: { $0.id == id }) else { return nil }
        return add(job.sourceURL, useAI: useAI ?? job.useAI, password: job.password)
    }

    func remove(_ id: UUID) {
        jobs.removeAll { $0.id == id }
    }

    private func enqueue(_ id: UUID) {
        pendingJobIDs.append(id)
        startNextJob()
    }

    private func startNextJob() {
        guard activeTask == nil else { return }
        while pendingHeadIndex < pendingJobIDs.count {
            let id = pendingJobIDs[pendingHeadIndex]
            pendingHeadIndex += 1
            compactPendingQueueIfNeeded()
            guard !cancelledJobIDs.contains(id) else { continue }
            activeJobID = id
            activeTask = Task { [weak self] in
                await self?.runJob(id)
                await MainActor.run {
                    guard self?.activeJobID == id else { return }
                    self?.activeTask = nil
                    self?.activeJobID = nil
                    self?.startNextJob()
                }
            }
            return
        }
        pendingJobIDs.removeAll(keepingCapacity: true)
        pendingHeadIndex = 0
    }

    private func compactPendingQueueIfNeeded() {
        guard pendingHeadIndex > 128, pendingHeadIndex * 2 > pendingJobIDs.count else { return }
        pendingJobIDs.removeFirst(pendingHeadIndex)
        pendingHeadIndex = 0
    }

    private func runJob(_ id: UUID) async {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        guard !cancelledJobIDs.contains(id), !Task.isCancelled else { return }
        update(id, stage: .copying)

        var lastReportedStage: ConversionStage = .copying
        let result = await runHandler(job) { [weak self] stage in
            lastReportedStage = stage
            Task { @MainActor in
                guard self?.cancelledJobIDs.contains(id) == false, !Task.isCancelled else { return }
                self?.update(id, stage: stage)
            }
        }

        guard !cancelledJobIDs.contains(id), !Task.isCancelled else { return }

        let stage: ConversionStage
        switch result {
        case .success:
            stage = .complete
        case .failure(let message):
            stage = message == ConversionError.cancelled.errorDescription ? .cancelled : .failed
            if message == ConversionError.passwordRequired.errorDescription {
                needsPassword = true
            }
        }

        finish(id, result: result, stage: stage, diagnosticStage: lastReportedStage)
    }

    private func update(_ id: UUID, stage: ConversionStage) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        guard jobs[index].isRunning else { return }
        jobs[index].stage = stage
        jobs[index].lastProgressAt = Date()
        jobs[index].isStalled = false
        AppLog.conversion.info("Conversion stage correlationID=\(id.uuidString, privacy: .public) stage=\(stage.rawValue, privacy: .public)")
    }

    private func markHeartbeat(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        guard jobs[index].isRunning else { return }
        jobs[index].lastProgressAt = Date()
        if jobs[index].isStalled {
            AppLog.conversion.info("Conversion progress resumed correlationID=\(id.uuidString, privacy: .public)")
        }
        jobs[index].isStalled = false
    }

    private func finish(_ id: UUID, result: ConversionResult, stage: ConversionStage, diagnosticStage: ConversionStage? = nil) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        guard jobs[index].stage != .cancelled || stage == .cancelled else { return }
        if stage == .failed {
            lastFailedJobContext = DiagnosticJobContext(
                correlationID: id.uuidString,
                stage: diagnosticStage ?? jobs[index].stage,
                errorCode: result.diagnosticCode
            )
        }
        jobs[index].stage = stage
        jobs[index].result = result
        jobs[index].lastProgressAt = Date()
        jobs[index].isStalled = false
        latestResult = result
        AppLog.conversion.info("Finished conversion correlationID=\(id.uuidString, privacy: .public) stage=\(stage.rawValue, privacy: .public)")
        continuations.removeValue(forKey: id)?.resume(returning: result)
    }

    private func startLivenessMonitorIfNeeded() {
        guard livenessTask == nil else { return }
        livenessTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    self?.classifyStalledJobs()
                }
            }
        }
    }

    private func classifyStalledJobs(referenceDate: Date = Date()) {
        var hasRunningJob = false
        for index in jobs.indices {
            guard jobs[index].isRunning else { continue }
            hasRunningJob = true
            let stalled = jobs[index].hasNoRecentProgress(referenceDate: referenceDate, threshold: livenessThreshold)
            if stalled, !jobs[index].isStalled {
                jobs[index].isStalled = true
                AppLog.conversion.warning("Conversion stalled correlationID=\(self.jobs[index].correlationID, privacy: .public) stage=\(self.jobs[index].stage.rawValue, privacy: .public)")
            }
        }
        if !hasRunningJob {
            livenessTask?.cancel()
            livenessTask = nil
        }
    }
}

private struct DiagnosticJobContext {
    let correlationID: String
    let stage: ConversionStage
    let errorCode: String?
}
