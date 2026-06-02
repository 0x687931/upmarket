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

    var isRunning: Bool {
        self == .queued || self == .copying || self == .extracting || self == .python || self == .postProcessing
    }
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
    var isStalled: Bool

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        useAI: Bool = false,
        password: String? = nil,
        createdAt: Date = Date(),
        stage: ConversionStage = .queued,
        result: ConversionResult? = nil,
        lastProgressAt: Date = Date(),
        isStalled: Bool = false
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.useAI = useAI
        self.password = password
        self.createdAt = createdAt
        self.stage = stage
        self.result = result
        self.lastProgressAt = lastProgressAt
        self.isStalled = isStalled
    }

    var name: String { sourceURL.deletingPathExtension().lastPathComponent }
    var ext: String { sourceURL.pathExtension.uppercased() }
    var correlationID: String { id.uuidString }
    var isRunning: Bool { stage.isRunning }

    // Scalar progress used by arc ring and progress bar.
    // Python stage owns the widest band because it is the longest phase.
    // When the Python bridge emits fractional heartbeats, replace the .python
    // case with an interpolation between 0.20 and 0.88 using pythonFraction.
    var progress: Double {
        switch stage {
        case .queued:         return 0.0
        case .copying:        return 0.08
        case .extracting:     return 0.20
        case .python:         return 0.55
        case .postProcessing: return 0.88
        case .complete:       return 1.0
        case .failed:         return 1.0
        case .cancelled:      return 1.0
        }
    }

    func hasNoRecentProgress(referenceDate: Date = Date(), threshold: TimeInterval) -> Bool {
        isRunning && referenceDate.timeIntervalSince(lastProgressAt) >= threshold
    }
}
