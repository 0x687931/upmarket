import Combine
import Foundation

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
    private var lastOperation: Task<Void, Never>?
    private var continuations: [UUID: CheckedContinuation<ConversionResult, Never>] = [:]
    private var cancelledJobIDs: Set<UUID> = []

    var isConverting: Bool {
        jobs.contains { $0.isRunning }
    }

    func stalledJobs(referenceDate: Date = Date(), threshold: TimeInterval = 60) -> [ConversionJob] {
        jobs.filter { $0.isStalled(referenceDate: referenceDate, threshold: threshold) }
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
        enqueue(job.id)
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
        finish(id, result: .failure(ConversionError.cancelled.errorDescription ?? "Conversion cancelled."), stage: .cancelled)
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
        let previous = lastOperation
        let task = Task { [weak self] in
            await previous?.value
            await self?.runJob(id)
        }
        lastOperation = task
    }

    private func runJob(_ id: UUID) async {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        guard !cancelledJobIDs.contains(id) else { return }
        update(id, stage: .copying)

        let result = await runHandler(job) { [weak self] stage in
            Task { @MainActor in
                guard self?.cancelledJobIDs.contains(id) == false else { return }
                self?.update(id, stage: stage)
            }
        }

        guard !cancelledJobIDs.contains(id) else { return }

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

        finish(id, result: result, stage: stage)
    }

    private func update(_ id: UUID, stage: ConversionStage) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].stage = stage
        jobs[index].lastProgressAt = Date()
    }

    private func finish(_ id: UUID, result: ConversionResult, stage: ConversionStage) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        guard jobs[index].stage != .cancelled || stage == .cancelled else { return }
        jobs[index].stage = stage
        jobs[index].result = result
        jobs[index].lastProgressAt = Date()
        latestResult = result
        continuations.removeValue(forKey: id)?.resume(returning: result)
    }
}
