import XCTest
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

    func testRunningJobCanBeClassifiedAsStalledWithoutCancellingIt() {
        let job = ConversionJob(
            sourceURL: URL(fileURLWithPath: "/tmp/stalled.pdf"),
            stage: .python,
            lastProgressAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertTrue(job.isStalled(referenceDate: Date(timeIntervalSince1970: 165), threshold: 60))
        XCTAssertTrue(job.isRunning)
        XCTAssertEqual(job.stage, .python)
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

    func testPythonBridgeFailureIsStoredPerJob() async {
        let queue = ConversionQueue { _, progress in
            progress?(.python)
            return .failure(ConversionError.pythonRuntime("Bridge unavailable").errorDescription!)
        }

        let id = queue.add(URL(fileURLWithPath: "/tmp/python.pdf"))
        await waitForResult(id, in: queue)

        let job = queue.jobs.first { $0.id == id }
        XCTAssertEqual(job?.stage, .failed)
        XCTAssertEqual(job?.result?.errorMessage, "The conversion engine couldn't start. Please try again.")
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

    private func waitForResult(_ id: UUID, in queue: ConversionQueue) async {
        for _ in 0..<100 {
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
        for _ in 0..<100 {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for condition")
    }
}
