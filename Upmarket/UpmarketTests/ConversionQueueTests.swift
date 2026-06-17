import XCTest
import AppKit
import CoreText
import PDFKit
@testable import Upmarket

@MainActor
final class ConversionQueueTests: XCTestCase {
    func testQueueRunsJobsSerially() async {
        var events: [String] = []
        let queue = ConversionQueue { job, progress in
            events.append("start:\(job.name)")
            progress?(.extracting)
            try? await Task.sleep(nanoseconds: 20_000_000)
            events.append("finish:\(job.name)")
            return .success(ConversionOutput(
                markdown: "# \(job.name)",
                pages: 1,
                format: job.ext,
                title: job.name,
                pipeline: .fast
            ))
        }

        let first = queue.add(URL(fileURLWithPath: "/tmp/first.pdf"))
        let second = queue.add(URL(fileURLWithPath: "/tmp/second.pdf"))

        await waitForResult(first, in: queue)
        await waitForResult(second, in: queue)

        XCTAssertEqual(events, [
            "start:first",
            "finish:first",
            "start:second",
            "finish:second"
        ])
        XCTAssertEqual(queue.jobs.first(where: { $0.id == first })?.stage, .complete)
        XCTAssertEqual(queue.jobs.first(where: { $0.id == second })?.stage, .complete)
    }

    func testBatchShelfQueueFiveMixedInputsWithFailureCancellationAndRetry() async {
        var events: [String] = []
        var attempts: [String: Int] = [:]
        let queue = ConversionQueue { job, progress in
            attempts[job.name, default: 0] += 1
            events.append("start:\(job.name)#\(attempts[job.name]!)")
            progress?(.extracting)
            try? await Task.sleep(nanoseconds: 20_000_000)
            if Task.isCancelled {
                return .failure(ConversionError.cancelled.errorDescription ?? "Conversion cancelled.")
            }
            if job.name == "bad" {
                return .failure("Unsupported file")
            }
            if job.name == "retry" && attempts[job.name] == 1 {
                return .failure("Transient extraction failure")
            }
            return .success(ConversionOutput(
                markdown: "# \(job.name)",
                pages: 1,
                format: job.ext,
                title: job.name,
                pipeline: .fast
            ))
        }

        let first = queue.add(URL(fileURLWithPath: "/tmp/first.pdf"))
        let bad = queue.add(URL(fileURLWithPath: "/tmp/bad.docx"))
        let retry = queue.add(URL(fileURLWithPath: "/tmp/retry.html"))
        let cancelled = queue.add(URL(fileURLWithPath: "/tmp/cancelled.pptx"))
        let last = queue.add(URL(fileURLWithPath: "/tmp/last.xlsx"))
        queue.cancel(cancelled)

        await waitForResult(first, in: queue)
        await waitForResult(bad, in: queue)
        await waitForResult(retry, in: queue)
        let retryAgain = queue.retry(retry)
        XCTAssertNotNil(retryAgain)
        await waitForResult(retryAgain!, in: queue)
        await waitForResult(last, in: queue)

        XCTAssertEqual(queue.job(id: first)?.stage, .complete)
        XCTAssertEqual(queue.job(id: bad)?.stage, .failed)
        XCTAssertEqual(queue.job(id: retry)?.stage, .failed)
        XCTAssertEqual(queue.job(id: retryAgain!)?.stage, .complete)
        XCTAssertEqual(queue.job(id: cancelled)?.stage, .cancelled)
        XCTAssertEqual(queue.job(id: last)?.stage, .complete)
        XCTAssertEqual(queue.job(id: bad)?.result?.errorMessage, "Unsupported file")
        XCTAssertEqual(queue.job(id: retry)?.result?.errorMessage, "Transient extraction failure")
        XCTAssertEqual(queue.job(id: cancelled)?.result?.errorMessage, ConversionError.cancelled.errorDescription)
        XCTAssertEqual(queue.job(id: retryAgain!)?.result?.output?.title, "retry")
        XCTAssertFalse(queue.isConverting)
        XCTAssertEqual(events, [
            "start:first#1",
            "start:bad#1",
            "start:retry#1",
            "start:last#1",
            "start:retry#2"
        ])
    }

    func testCancelPreventsQueuedJobFromRunning() async {
        var started: [String] = []
        let queue = ConversionQueue { job, _ in
            started.append(job.name)
            try? await Task.sleep(nanoseconds: 20_000_000)
            return .success(ConversionOutput(
                markdown: job.name,
                pages: 1,
                format: job.ext,
                title: job.name,
                pipeline: .fast
            ))
        }

        let first = queue.add(URL(fileURLWithPath: "/tmp/first.pdf"))
        let second = queue.add(URL(fileURLWithPath: "/tmp/second.pdf"))
        queue.cancel(second)

        await waitForResult(first, in: queue)

        XCTAssertEqual(started, ["first"])
        XCTAssertEqual(queue.jobs.first(where: { $0.id == second })?.stage, .cancelled)
        XCTAssertEqual(queue.jobs.first(where: { $0.id == second })?.result?.errorMessage, ConversionError.cancelled.errorDescription)
    }

    func testSuccessfulJobPersistsHistoryRecord() async {
        let history = makeHistoryStore()
        let queue = ConversionQueue(runHandler: { job, _ in
            .success(ConversionOutput(
                markdown: "# Persisted\n\nBody text",
                pages: 2,
                format: job.ext,
                title: "Persisted",
                pipeline: .fast,
                selectedPathway: .pdfKit
            ))
        }, historyStore: history)

        let id = queue.add(URL(fileURLWithPath: "/Users/alice/Documents/persisted.pdf"))
        await waitForResult(id, in: queue)

        XCTAssertEqual(history.records.count, 1)
        XCTAssertEqual(history.records[0].sourceDisplayName, "persisted.pdf")
        XCTAssertEqual(history.records[0].sourceExtension, "PDF")
        XCTAssertEqual(history.records[0].selectedPathway, .pdfKit)
        XCTAssertEqual(history.records[0].markdown, "# Persisted\n\nBody text")
        XCTAssertFalse(history.records[0].sourceDisplayName.contains("/Users/alice"))
    }

    func testCancelRunningJobStartsNextQueuedJob() async {
        var started: [String] = []
        let queue = ConversionQueue { job, _ in
            started.append(job.name)
            if job.name == "first" {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            return .success(ConversionOutput(
                markdown: job.name,
                pages: 1,
                format: job.ext,
                title: job.name,
                pipeline: .fast
            ))
        }

        let first = queue.add(URL(fileURLWithPath: "/tmp/first.pdf"))
        let second = queue.add(URL(fileURLWithPath: "/tmp/second.pdf"))
        await waitUntil { started == ["first"] }

        queue.cancel(first)
        await waitForResult(second, in: queue)

        XCTAssertEqual(queue.jobs.first(where: { $0.id == first })?.stage, .cancelled)
        XCTAssertTrue(started.contains("second"))
        XCTAssertEqual(queue.jobs.first(where: { $0.id == second })?.stage, .complete)
    }

    func testCancelRunningJobDoesNotOverlapSlowRunnerWithNextJob() async {
        var events: [String] = []
        var releaseFirst: CheckedContinuation<Void, Never>?
        let queue = ConversionQueue { job, _ in
            events.append("start:\(job.name)")
            if job.name == "first" {
                await withCheckedContinuation { continuation in
                    releaseFirst = continuation
                }
                events.append("unwound:first")
                return .failure(ConversionError.cancelled.errorDescription ?? "Conversion cancelled.")
            }
            events.append("finish:\(job.name)")
            return .success(ConversionOutput(
                markdown: job.name,
                pages: 1,
                format: job.ext,
                title: job.name,
                pipeline: .fast
            ))
        }

        let first = queue.add(URL(fileURLWithPath: "/tmp/first.pdf"))
        let second = queue.add(URL(fileURLWithPath: "/tmp/second.pdf"))
        await waitUntil { events == ["start:first"] }

        queue.cancel(first)
        await sleep(milliseconds: 80)

        XCTAssertEqual(queue.job(id: first)?.stage, .cancelled)
        XCTAssertEqual(queue.job(id: first)?.result?.errorMessage, ConversionError.cancelled.errorDescription)
        XCTAssertEqual(events, ["start:first"])

        releaseFirst?.resume()
        await waitForResult(second, in: queue)

        XCTAssertEqual(events, [
            "start:first",
            "unwound:first",
            "start:second",
            "finish:second"
        ])
        XCTAssertEqual(queue.job(id: first)?.stage, .cancelled)
        XCTAssertEqual(queue.job(id: second)?.stage, .complete)
    }

    func testCancelAllCancelsActiveAndQueuedJobs() async {
        var started: [String] = []
        let queue = ConversionQueue { job, _ in
            started.append(job.name)
            try? await Task.sleep(nanoseconds: 200_000_000)
            if Task.isCancelled {
                return .failure(ConversionError.cancelled.errorDescription ?? "Conversion cancelled.")
            }
            return .success(ConversionOutput(
                markdown: job.name,
                pages: 1,
                format: job.ext,
                title: job.name,
                pipeline: .fast
            ))
        }

        let first = queue.add(URL(fileURLWithPath: "/tmp/first.pdf"))
        let second = queue.add(URL(fileURLWithPath: "/tmp/second.pdf"))
        await waitUntil { started == ["first"] }

        queue.cancelAll()

        XCTAssertEqual(queue.jobs.first(where: { $0.id == first })?.stage, .cancelled)
        XCTAssertEqual(queue.jobs.first(where: { $0.id == second })?.stage, .cancelled)
        XCTAssertNil(queue.latestResult)
        XCTAssertFalse(queue.isConverting)
    }

    func testRunningJobCanBeClassifiedAsStalledWithoutCancellingIt() {
        let job = ConversionJob(
            sourceURL: URL(fileURLWithPath: "/tmp/stalled.pdf"),
            stage: .processing,
            lastProgressAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertTrue(job.hasNoRecentProgress(referenceDate: Date(timeIntervalSince1970: 165), threshold: 60))
        XCTAssertTrue(job.isRunning)
        XCTAssertEqual(job.stage, .processing)
    }

    func testProgressClearsRecoverableStalledState() async {
        let queue = ConversionQueue { _, progress in
            progress?(.processing)
            try? await Task.sleep(nanoseconds: 20_000_000)
            progress?(.postProcessing)
            return .success(ConversionOutput(
                markdown: "ok",
                pages: 1,
                format: "PDF",
                title: "stalled",
                pipeline: .fast
            ))
        }

        let id = queue.add(URL(fileURLWithPath: "/tmp/stalled.pdf"))
        await waitUntil {
            queue.jobs.first(where: { $0.id == id })?.stage == .processing
        }

        XCTAssertFalse(queue.jobs.first(where: { $0.id == id })?.isStalled ?? true)
        await waitForResult(id, in: queue)
        XCTAssertEqual(queue.jobs.first(where: { $0.id == id })?.stage, .complete)
        XCTAssertFalse(queue.jobs.first(where: { $0.id == id })?.isStalled ?? true)
    }

    func testPythonProgressFractionAdvancesWithinPythonBand() async {
        let queue = ConversionQueue { _, progress in
            progress?(ConversionProgress(stage: .processing, fraction: 0.25, message: "Processing"))
            try? await Task.sleep(nanoseconds: 30_000_000)
            progress?(ConversionProgress(stage: .processing, fraction: 0.75, message: "Processing"))
            try? await Task.sleep(nanoseconds: 30_000_000)
            return .success(ConversionOutput(
                markdown: "ok",
                pages: 1,
                format: "PDF",
                title: "progress",
                pipeline: .enhanced,
                selectedPathway: .enhanced
            ))
        }

        let id = queue.add(URL(fileURLWithPath: "/tmp/progress.pdf"))
        await waitUntil {
            guard let job = queue.job(id: id), job.stage == .processing else { return false }
            return job.progress > 0.35 && job.progress < 0.45
        }
        let firstProgress = queue.job(id: id)?.progress ?? 0

        await waitUntil {
            guard let job = queue.job(id: id), job.stage == .processing else { return false }
            return job.progress > 0.65
        }
        let secondProgress = queue.job(id: id)?.progress ?? 0

        XCTAssertGreaterThan(secondProgress, firstProgress)
        await waitForResult(id, in: queue)
        XCTAssertEqual(queue.job(id: id)?.stage, .complete)
        XCTAssertEqual(queue.job(id: id)?.progress, 1.0)
    }

    func testCriticalMemoryPressureFailsRunningJobsRecoverably() async {
        let queue = ConversionQueue { _, _ in
            try? await Task.sleep(nanoseconds: 200_000_000)
            return .success(ConversionOutput(
                markdown: "late",
                pages: 1,
                format: "PDF",
                title: "late",
                pipeline: .fast
            ))
        }

        let id = queue.add(URL(fileURLWithPath: "/tmp/memory.pdf"))
        await waitUntil {
            queue.jobs.first(where: { $0.id == id })?.isRunning == true
        }

        queue.handleMemoryPressureCritical()

        let job = queue.jobs.first { $0.id == id }
        XCTAssertEqual(job?.stage, .failed)
        XCTAssertEqual(job?.result?.errorMessage, ConversionError.memoryPressure.errorDescription)
        XCTAssertFalse(job?.isRunning ?? true)
    }

    func testFailureIsStoredPerJob() async {
        let queue = ConversionQueue { _, progress in
            progress?(.extracting)
            return .failure("Unsupported file")
        }

        let id = queue.add(URL(fileURLWithPath: "/tmp/bad.bin"))

        await waitForResult(id, in: queue)

        let job = queue.jobs.first { $0.id == id }
        XCTAssertEqual(job?.stage, .failed)
        XCTAssertEqual(job?.result?.errorMessage, "Unsupported file")
    }

    func testRejectedInputCreatesVisibleFailedJobWithoutRunningQueue() {
        var didRun = false
        let queue = ConversionQueue { _, _ in
            didRun = true
            return .failure("Should not run")
        }
        let message = FileAccessError.unsupportedType.errorDescription!

        let id = queue.addRejected(URL(fileURLWithPath: "/tmp/rejected"), message: message)

        let job = queue.jobs.first { $0.id == id }
        XCTAssertEqual(job?.stage, .failed)
        XCTAssertEqual(job?.result?.errorMessage, message)
        XCTAssertEqual(queue.latestResult?.errorMessage, message)
        XCTAssertFalse(queue.isConverting)
        XCTAssertFalse(didRun)
    }

    func testJobLookupKeepsTrackedPasswordJobSeparateFromLatestResult() async {
        let passwordMessage = ConversionError.passwordRequired.errorDescription!
        let queue = ConversionQueue { job, _ in
            if job.name == "locked" {
                return .failure(passwordMessage)
            }
            return .success(ConversionOutput(
                markdown: "# Plain",
                pages: 1,
                format: "PDF",
                title: "plain",
                pipeline: .fast
            ))
        }

        let locked = queue.add(URL(fileURLWithPath: "/tmp/locked.pdf"))
        let plain = queue.add(URL(fileURLWithPath: "/tmp/plain.pdf"))
        await waitForResult(locked, in: queue)
        await waitForResult(plain, in: queue)

        XCTAssertEqual(queue.job(id: locked)?.result?.errorMessage, passwordMessage)
        XCTAssertEqual(queue.job(id: plain)?.result?.output?.title, "plain")
        XCTAssertEqual(queue.latestResult?.output?.title, "plain")
    }

    func testTrackedRunningJobSurvivesAdjacentRejectedInputLatestResult() async {
        let queue = ConversionQueue { _, _ in
            try? await Task.sleep(nanoseconds: 100_000_000)
            return .success(ConversionOutput(
                markdown: "# Primary",
                pages: 1,
                format: "PDF",
                title: "primary",
                pipeline: .fast
            ))
        }

        let primary = queue.add(URL(fileURLWithPath: "/tmp/primary.pdf"))
        await waitUntil {
            queue.job(id: primary)?.isRunning == true
        }

        let rejectedMessage = FileAccessError.unsupportedType.errorDescription!
        let rejected = queue.addRejected(URL(fileURLWithPath: "/tmp/rejected"), message: rejectedMessage)

        XCTAssertTrue(queue.job(id: primary)?.isRunning ?? false)
        XCTAssertEqual(queue.job(id: rejected)?.result?.errorMessage, rejectedMessage)
        XCTAssertEqual(queue.latestResult?.errorMessage, rejectedMessage)
        await waitForResult(primary, in: queue)
    }

    func testEngineFailureIsStoredPerJob() async {
        let queue = ConversionQueue { _, progress in
            progress?(.processing)
            return .failure(ConversionError.engineFailed("Engine unavailable").errorDescription!)
        }

        let id = queue.add(URL(fileURLWithPath: "/tmp/python.pdf"))
        await waitForResult(id, in: queue)

        let job = queue.jobs.first { $0.id == id }
        XCTAssertEqual(job?.stage, .failed)
        XCTAssertEqual(job?.result?.errorMessage, "The conversion engine couldn't start. Please try again.")
    }

    func testJobsAlwaysResolveToTerminalResultOrExplicitInProgressState() async {
        let passwordMessage = ConversionError.passwordRequired.errorDescription!
        var releaseRunning: CheckedContinuation<Void, Never>?
        let queue = ConversionQueue { job, _ in
            switch job.name {
            case "success":
                return .success(ConversionOutput(
                    markdown: "# Success",
                    pages: 1,
                    format: "PDF",
                    title: "success",
                    pipeline: .fast
                ))
            case "password":
                return .failure(passwordMessage)
            case "running":
                await withCheckedContinuation { continuation in
                    releaseRunning = continuation
                }
                return .success(ConversionOutput(
                    markdown: "# Running",
                    pages: 1,
                    format: "PDF",
                    title: "running",
                    pipeline: .fast
                ))
            default:
                return .failure("Unsupported file")
            }
        }

        let success = queue.add(URL(fileURLWithPath: "/tmp/success.pdf"))
        let failed = queue.add(URL(fileURLWithPath: "/tmp/failed.pdf"))
        let password = queue.add(URL(fileURLWithPath: "/tmp/password.pdf"))
        let running = queue.add(URL(fileURLWithPath: "/tmp/running.pdf"))

        await waitForResult(success, in: queue)
        await waitForResult(failed, in: queue)
        await waitForResult(password, in: queue)
        await waitUntil {
            queue.job(id: running)?.isRunning == true
        }

        assertResolved(queue.job(id: success), expectedStage: .complete, file: #filePath, line: #line)
        assertResolved(queue.job(id: failed), expectedStage: .failed, file: #filePath, line: #line)
        assertResolved(queue.job(id: password), expectedStage: .failed, file: #filePath, line: #line)
        XCTAssertTrue(queue.needsPassword)

        let runningJob = queue.job(id: running)
        XCTAssertTrue(runningJob?.isRunning ?? false)
        XCTAssertNil(runningJob?.result)

        releaseRunning?.resume()
        await waitForResult(running, in: queue)
        assertResolved(queue.job(id: running), expectedStage: .complete, file: #filePath, line: #line)
    }

    func testRetryCreatesNewJobForOriginalSource() async {
        var attempts = 0
        let queue = ConversionQueue { job, _ in
            attempts += 1
            if attempts == 1 { return .failure("Try again") }
            return .success(ConversionOutput(
                markdown: job.name,
                pages: 1,
                format: job.ext,
                title: job.name,
                pipeline: .fast
            ))
        }

        let first = queue.add(URL(fileURLWithPath: "/tmp/retry.pdf"))
        await waitForResult(first, in: queue)

        let second = queue.retry(first)
        XCTAssertNotNil(second)
        await waitForResult(second!, in: queue)

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(queue.jobs.first(where: { $0.id == first })?.stage, .failed)
        XCTAssertEqual(queue.jobs.first(where: { $0.id == second })?.stage, .complete)
    }

    // MARK: - Liveness monitor

    func testLivenessMonitorClassifiesJobStalledAfterThreshold() async {
        var blocker: CheckedContinuation<Void, Never>?
        let queue = ConversionQueue { _, progress in
            progress?(.processing)
            await withCheckedContinuation { continuation in
                blocker = continuation
            }
            return .success(ConversionOutput(markdown: "ok", pages: 1, format: "PDF", title: "stalled", pipeline: .fast))
        }

        let id = queue.add(URL(fileURLWithPath: "/tmp/stalled.pdf"))
        await waitUntil { queue.job(id: id)?.stage == .processing }

        // Simulate 65s elapsed since last progress — crosses the 60s threshold.
        queue.classifyStalledJobsForTesting(referenceDate: Date(timeIntervalSinceNow: 65))

        XCTAssertTrue(queue.job(id: id)?.isStalled ?? false)
        blocker?.resume()
        await waitForResult(id, in: queue)
    }

    func testLivenessMonitorClearsIsStalled_WhenProgressArrives() async {
        let blocker = TaskBlocker()
        let queue = ConversionQueue { _, progress in
            progress?(.processing)
            await blocker.wait()
            progress?(.postProcessing)
            return .success(ConversionOutput(markdown: "ok", pages: 1, format: "PDF", title: "recover", pipeline: .fast))
        }

        let id = queue.add(URL(fileURLWithPath: "/tmp/recover.pdf"))
        await waitUntil { queue.job(id: id)?.stage == .processing }

        // Force stalled via the test hook
        queue.classifyStalledJobsForTesting(referenceDate: Date(timeIntervalSinceNow: 65))
        XCTAssertTrue(queue.job(id: id)?.isStalled ?? false)

        // Unblock the runner — postProcessing progress fires, which calls update(), which clears isStalled
        await blocker.unblock()
        await waitForResult(id, in: queue)
        XCTAssertFalse(queue.job(id: id)?.isStalled ?? true)
    }

    func testLivenessMonitorStopsWhenNoRunningJobs() async {
        let queue = ConversionQueue { _, _ in
            try? await Task.sleep(nanoseconds: 10_000_000)
            return .success(ConversionOutput(markdown: "ok", pages: 1, format: "PDF", title: "done", pipeline: .fast))
        }

        let id = queue.add(URL(fileURLWithPath: "/tmp/done.pdf"))
        XCTAssertTrue(queue.hasActiveLivenessTaskForTesting)
        await waitForResult(id, in: queue)

        // Drive classifyStalledJobs directly — the real timer fires every 5s which is too slow for tests.
        // When no jobs are running, classifyStalledJobs cancels and nils the liveness task.
        queue.classifyStalledJobsForTesting()
        XCTAssertFalse(queue.hasActiveLivenessTaskForTesting)
    }

    func testRunnerCleansWorkspaceWhenInputCopyFails() async {
        AppWorkspace.removeStaleWorkspaces()
        let before = workspaceNames()
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString)")
            .appendingPathExtension("pdf")

        let result = await ConversionRunner().run(ConversionJob(sourceURL: missing))

        XCTAssertEqual(result.errorMessage, ConversionError.sourceUnavailable.errorDescription)
        XCTAssertEqual(workspaceNames(), before)
    }

    func testRunnerCleansWorkspaceAfterSuccessfulNativeConversion() async throws {
        AppWorkspace.removeStaleWorkspaces()
        let before = workspaceNames()
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpmarketCleanupSuccess-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: workspace)
        }
        let pdf = workspace.appendingPathComponent("success.pdf")
        try writePDF(to: pdf, text: "Cleanup success")

        let result = await ConversionRunner(supportsAdvancedRuntime: false)
            .run(ConversionJob(sourceURL: pdf))

        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(workspaceNames(), before)
    }

    func testRunnerCleansWorkspaceAfterRecoverableFailure() async throws {
        AppWorkspace.removeStaleWorkspaces()
        let before = workspaceNames()
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpmarketCleanupFailure-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: workspace)
        }
        let docx = workspace.appendingPathComponent("failure.docx")
        try Data("not a real docx, but enough to prove cleanup".utf8).write(to: docx)

        let result = await ConversionRunner(supportsAdvancedRuntime: false)
            .run(ConversionJob(sourceURL: docx))

        // DOCX converts natively in the Basic tier; an invalid container fails native
        // parsing with `.inaccessible`. The workspace must still be cleaned up.
        XCTAssertEqual(result.errorMessage, ConversionError.inaccessible.errorDescription)
        XCTAssertEqual(workspaceNames(), before)
    }

    func testNativeOnlyRuntimeRejectsPythonBackedFormats() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpmarketNativeOnlyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: workspace)
        }
        // ZIP/WEBVTT were Python-only formats with no native engine. With the Python
        // runtime removed they are no longer accepted input types, so they are rejected at
        // input validation. (DOCX/TXT/CSV/EPUB now convert natively — see the
        // native-conversion tests below.)
        let zip = workspace.appendingPathComponent("structured.zip")
        try Data("not a real zip, but enough to prove routing".utf8).write(to: zip)

        let result = await ConversionRunner(supportsAdvancedRuntime: false)
            .run(ConversionJob(sourceURL: zip))

        XCTAssertEqual(result.errorMessage, ConversionError.inaccessible.errorDescription)
    }

    func testNativeOnlyRuntimeConvertsPlainTextFormats() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpmarketNativeTextTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: workspace)
        }

        let txt = workspace.appendingPathComponent("note.txt")
        try "Hello from plain text".write(to: txt, atomically: true, encoding: .utf8)
        let txtResult = await ConversionRunner(supportsAdvancedRuntime: false)
            .run(ConversionJob(sourceURL: txt))
        XCTAssertNil(txtResult.errorMessage)
        XCTAssertEqual(txtResult.output?.selectedPathway, .nativeText)
        XCTAssertTrue(txtResult.output?.markdown.contains("Hello from plain text") ?? false)

        let csv = workspace.appendingPathComponent("data.csv")
        try "Name,Score\nAda,99\nGrace,100".write(to: csv, atomically: true, encoding: .utf8)
        let csvResult = await ConversionRunner(supportsAdvancedRuntime: false)
            .run(ConversionJob(sourceURL: csv))
        XCTAssertNil(csvResult.errorMessage)
        XCTAssertEqual(csvResult.output?.selectedPathway, .nativeText)
        // Rendered as a Markdown table (assert content/structure, not exact column padding,
        // which post-processing may normalise).
        let csvMarkdown = csvResult.output?.markdown ?? ""
        XCTAssertTrue(csvMarkdown.contains("|"), "CSV must render as a Markdown table")
        XCTAssertTrue(csvMarkdown.contains("---"), "CSV table must have a header separator row")
        for token in ["Name", "Score", "Ada", "99", "Grace", "100"] {
            XCTAssertTrue(csvMarkdown.contains(token), "CSV table missing \(token)")
        }
    }

    func testScannedImageRoutesThroughVisionImageOCR() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpmarketScannedImageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: workspace)
        }

        // Render text into a PNG so the classifier sees a scanned-image document (≥10 words)
        // and routes it to the image-specific Vision OCR path — not the PDF-only quality path.
        let size = NSSize(width: 1000, height: 300)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let sentence = "The quick brown fox jumps over the lazy dog near the river bank today"
        NSAttributedString(
            string: sentence,
            attributes: [.font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black]
        ).draw(at: NSPoint(x: 20, y: 120))
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("Expected to render a PNG fixture")
        }
        let imageURL = workspace.appendingPathComponent("scanned.png")
        try png.write(to: imageURL)

        // Force the scanned-document classification so the test deterministically exercises
        // the image-OCR routing fix — a synthetic PNG can otherwise classify as photo/artwork
        // (metadata-only). This guards the regression: a scanned image must use the image
        // Vision-OCR path, not the PDF-only quality path.
        let scanned = ContentClassifier.Classification(
            kind: .scannedDocument, requiredTier: .native, hasExtractableText: false,
            frameCount: 1, pdfEvidence: nil, recommendedPathway: .visionOCR
        )
        let result = await ConversionRunner(
            supportsAdvancedRuntime: false, supportsAI: false,
            classifyOverride: { _, _, _, _ in scanned }
        ).run(ConversionJob(sourceURL: imageURL))

        // The PDF-only path would fail to open a bare image; the image route must succeed.
        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(result.output?.selectedPathway, .visionOCR)
    }

    func testNativeOnlyRuntimeStillConvertsDigitalPDF() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpmarketNativePDFTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: workspace)
        }
        let pdf = workspace.appendingPathComponent("native.pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 400, height: 300)
        guard let context = CGContext(pdf as CFURL, mediaBox: &mediaBox, nil) else {
            return XCTFail("Expected PDF context")
        }
        context.beginPDFPage(nil)
        let text = NSAttributedString(
            string: "Native PDF conversion",
            attributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.black]
        )
        context.textPosition = CGPoint(x: 40, y: 150)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        context.endPDFPage()
        context.closePDF()

        let result = await ConversionRunner(supportsAdvancedRuntime: false)
            .run(ConversionJob(sourceURL: pdf))

        XCTAssertNil(result.errorMessage)
        XCTAssertEqual(result.output?.format, "PDF")
        XCTAssertTrue(result.output?.markdown.contains("Native PDF conversion") ?? false)
        XCTAssertEqual(result.output?.selectedPathway, .pdfKit)
    }

    private func writePDF(to url: URL, text: String) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 400, height: 300)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "ConversionQueueTests", code: 1)
        }
        context.beginPDFPage(nil)
        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.black]
        )
        context.textPosition = CGPoint(x: 40, y: 150)
        CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        context.endPDFPage()
        context.closePDF()
    }

    // MARK: - Helpers

    // Cap at ~10s, not 1s: a real conversion (classify + PDFKit/Vision) under CI load can take
    // several seconds, which intermittently failed these waiters. The loop returns as soon as the
    // condition holds, so fast runs stay fast — this only widens the ceiling.
    private func waitForResult(_ id: UUID, in queue: ConversionQueue) async {
        for _ in 0..<1000 {
            if let job = queue.jobs.first(where: { $0.id == id }),
               job.result != nil,
               !job.isRunning {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for conversion job \(id)")
    }

    private func waitUntil(_ predicate: @escaping () -> Bool) async {
        for _ in 0..<1000 {
            if predicate() { return }
            await sleep(milliseconds: 10)
        }
        XCTFail("Timed out waiting for condition")
    }

    private func sleep(milliseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    private func assertResolved(
        _ job: ConversionJob?,
        expectedStage: ConversionStage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(job?.stage, expectedStage, file: file, line: line)
        XCTAssertFalse(job?.isRunning ?? true, file: file, line: line)
        XCTAssertNotNil(job?.result, file: file, line: line)
    }

    private func workspaceNames() -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: AppWorkspace.baseDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        return entries.map(\.lastPathComponent).sorted()
    }

    private func makeHistoryStore() -> ConversionHistoryStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpmarketQueueHistoryTests-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "UpmarketQueueHistoryTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suiteName)
        }
        return ConversionHistoryStore(
            directoryURL: directory,
            userDefaults: defaults,
            loadImmediately: false
        )
    }
}

private actor TaskBlocker {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { self.continuation = $0 }
    }

    func unblock() {
        continuation?.resume()
        continuation = nil
    }
}
