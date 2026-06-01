import Foundation

enum ConversionStage: String, Equatable {
    case queued
    case copying
    case extracting
    case python
    case postProcessing
    case complete
    case failed
    case cancelled
}

struct ConversionJob: Identifiable, Equatable {
    let id: UUID
    let sourceURL: URL
    let useAI: Bool
    let password: String?
    let createdAt: Date

    var stage: ConversionStage
    var result: ConversionResult?
    var lastProgressAt: Date

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        useAI: Bool = false,
        password: String? = nil,
        createdAt: Date = Date(),
        stage: ConversionStage = .queued,
        result: ConversionResult? = nil,
        lastProgressAt: Date = Date()
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.useAI = useAI
        self.password = password
        self.createdAt = createdAt
        self.stage = stage
        self.result = result
        self.lastProgressAt = lastProgressAt
    }

    var name: String { sourceURL.deletingPathExtension().lastPathComponent }
    var ext: String { sourceURL.pathExtension.uppercased() }
    var isRunning: Bool { stage == .queued || stage == .copying || stage == .extracting || stage == .python || stage == .postProcessing }

    func isStalled(referenceDate: Date = Date(), threshold: TimeInterval) -> Bool {
        isRunning && referenceDate.timeIntervalSince(lastProgressAt) >= threshold
    }
}
