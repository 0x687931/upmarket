import Foundation

nonisolated enum ConversionStage: String, Equatable, Sendable {
    case queued
    case copying
    case analysing
    case extracting
    case python
    case postProcessing
    case complete
    case failed
    case cancelled

    var isRunning: Bool {
        self == .queued || self == .copying || self == .analysing || self == .extracting || self == .python || self == .postProcessing
    }
}

nonisolated struct ConversionProgress: Equatable, Sendable {
    let stage: ConversionStage
    let fraction: Double?
    let message: String?

    init(stage: ConversionStage, fraction: Double? = nil, message: String? = nil) {
        self.stage = stage
        if let fraction, fraction.isFinite {
            self.fraction = min(max(fraction, 0), 1)
        } else {
            self.fraction = nil
        }
        self.message = message
    }

    static let queued = ConversionProgress(stage: .queued)
    static let copying = ConversionProgress(stage: .copying)
    static let analysing = ConversionProgress(stage: .analysing)
    static let extracting = ConversionProgress(stage: .extracting)
    static let python = ConversionProgress(stage: .python)
    static let postProcessing = ConversionProgress(stage: .postProcessing)
    static let complete = ConversionProgress(stage: .complete)
    static let failed = ConversionProgress(stage: .failed)
    static let cancelled = ConversionProgress(stage: .cancelled)
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
    var progressFraction: Double?

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        useAI: Bool = false,
        password: String? = nil,
        createdAt: Date = Date(),
        stage: ConversionStage = .queued,
        result: ConversionResult? = nil,
        lastProgressAt: Date = Date(),
        isStalled: Bool = false,
        progressFraction: Double? = nil
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
        self.progressFraction = progressFraction
    }

    var name: String { sourceURL.deletingPathExtension().lastPathComponent }
    var ext: String { sourceURL.pathExtension.uppercased() }
    var correlationID: String { id.uuidString }
    var isRunning: Bool { stage.isRunning }

    // Scalar progress used by arc ring and progress bar.
    // Python stage owns the widest band because it is the longest phase.
    var progress: Double {
        if let progressFraction, stage.isRunning {
            let band = progressBand
            return band.lower + ((band.upper - band.lower) * progressFraction)
        }
        switch stage {
        case .queued:         return 0.0
        case .copying:        return 0.06
        case .analysing:      return 0.12
        case .extracting:     return 0.20
        case .python:         return 0.55
        case .postProcessing: return 0.88
        case .complete:       return 1.0
        case .failed:         return 1.0
        case .cancelled:      return 1.0
        }
    }

    private var progressBand: (lower: Double, upper: Double) {
        switch stage {
        case .queued:         return (0.0, 0.0)
        case .copying:        return (0.01, 0.06)
        case .analysing:      return (0.06, 0.12)
        case .extracting:     return (0.12, 0.20)
        case .python:         return (0.20, 0.88)
        case .postProcessing: return (0.88, 0.96)
        case .complete:       return (1.0, 1.0)
        case .failed:         return (1.0, 1.0)
        case .cancelled:      return (1.0, 1.0)
        }
    }

    func hasNoRecentProgress(referenceDate: Date = Date(), threshold: TimeInterval) -> Bool {
        isRunning && referenceDate.timeIntervalSince(lastProgressAt) >= threshold
    }
}
