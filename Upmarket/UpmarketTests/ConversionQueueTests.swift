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

    private func waitForResult(_ id: UUID, in queue: ConversionQueue) async {
        for _ in 0..<100 {
            if queue.jobs.first(where: { $0.id == id })?.result != nil { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for conversion job \(id)")
    }
}
