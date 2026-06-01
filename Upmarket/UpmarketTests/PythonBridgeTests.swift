import XCTest
@testable import Upmarket

@MainActor
final class PythonBridgeTests: XCTestCase {
    func testBridgeErrorsAreTypedAndUserReadable() {
        XCTAssertEqual(
            PythonBridgeError.helperUnavailable("missing").localizedDescription,
            "Conversion engine is unavailable."
        )
        XCTAssertEqual(
            PythonBridgeError.helperCrashed("signal").localizedDescription,
            "Conversion engine stopped unexpectedly. Please try again."
        )
        XCTAssertEqual(
            PythonBridgeError.invalidResponse("bad").localizedDescription,
            "Conversion engine returned an unreadable result."
        )
        XCTAssertEqual(PythonBridgeError.helperUnavailable("missing").diagnosticCode, "runtime.helper.unavailable")
    }

    func testHelperReadinessImportSmokeSucceedsWhenPackagedRuntimeIsPresent() async throws {
        guard Bundle.main.url(forAuxiliaryExecutable: "UpmarketRuntimeHelper") != nil else {
            throw XCTSkip("Runtime helper is not embedded in this test bundle")
        }

        let status = try await RuntimeHelperClient(livenessInterval: 15).readiness()

        XCTAssertTrue(status.isReady)
        XCTAssertNotNil(status.version)
        XCTAssertNil(status.error)
    }

    func testConversionCallMapsSuccessResponse() async throws {
        let helper = try makeHelperScript("""
        #!/bin/sh
        printf '{"event":"heartbeat"}\\n'
        cat >/dev/null
        printf '{"success":true,"needsPassword":false,"output":{"markdown":"# Converted","pages":1,"format":"TXT","title":"Fixture","pipeline":"enhanced"}}\\n'
        """)
        let client = RuntimeHelperClient(executableURL: helper, livenessInterval: 2)

        let result = try await client.convert(
            fileURL: URL(fileURLWithPath: "/tmp/input.txt"),
            title: "Fixture",
            useAI: false,
            password: nil,
            workspaceURL: URL(fileURLWithPath: "/tmp")
        )

        XCTAssertEqual(result.output?.markdown, "# Converted")
        XCTAssertEqual(result.output?.pipeline, .enhanced)
    }

    func testHelperCrashMapsToTypedFailure() async throws {
        let helper = try makeHelperScript("""
        #!/bin/sh
        kill -9 $$
        """)
        let client = RuntimeHelperClient(executableURL: helper, livenessInterval: 2)

        do {
            _ = try await client.readiness()
            XCTFail("Expected helper crash")
        } catch let error as PythonBridgeError {
            XCTAssertEqual(error.diagnosticCode, "runtime.helper.crashed")
        }
    }

    func testHelperBadExitMapsToTypedFailure() async throws {
        let helper = try makeHelperScript("""
        #!/bin/sh
        cat >/dev/null
        exit 42
        """)
        let client = RuntimeHelperClient(executableURL: helper, livenessInterval: 2)

        do {
            _ = try await client.readiness()
            XCTFail("Expected bad exit")
        } catch let error as PythonBridgeError {
            XCTAssertEqual(error.diagnosticCode, "runtime.helper.bad-exit")
        }
    }

    func testInvalidResponseMapsToTypedFailure() async throws {
        let helper = try makeHelperScript("""
        #!/bin/sh
        printf '{"event":"heartbeat"}\\n'
        cat >/dev/null
        printf 'not-json\\n'
        """)
        let client = RuntimeHelperClient(executableURL: helper, livenessInterval: 2)

        do {
            _ = try await client.readiness()
            XCTFail("Expected invalid response")
        } catch let error as PythonBridgeError {
            XCTAssertEqual(error.diagnosticCode, "runtime.helper.invalid-response")
        }
    }

    func testHelperDrainsLargeStderrWithoutDeadlock() async throws {
        let helper = try makeHelperScript("""
        #!/bin/sh
        cat >/dev/null
        i=0
        while [ "$i" -lt 6000 ]; do
          printf 'runtime warning line %04d with enough bytes to exceed the pipe buffer\\n' "$i" >&2
          i=$((i + 1))
        done
        printf '{"success":true,"needsPassword":false,"output":{"markdown":"# Converted","pages":1,"format":"TXT","title":"Fixture","pipeline":"enhanced"}}\\n'
        """)
        let client = RuntimeHelperClient(executableURL: helper, livenessInterval: 2)

        let result = try await client.convert(
            fileURL: URL(fileURLWithPath: "/tmp/input.txt"),
            title: "Fixture",
            useAI: false,
            password: nil,
            workspaceURL: URL(fileURLWithPath: "/tmp")
        )

        XCTAssertEqual(result.output?.markdown, "# Converted")
    }

    func testPasswordProtectedCorpusPDFReturnsPasswordFailure() async throws {
        let fixture = corpusFixture("docling/docling/tests/data/pdf_password/2206.01062_pg3.pdf")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("Password PDF corpus fixture is not present")
        }

        let result = await ConversionRunner().run(ConversionJob(sourceURL: fixture))

        XCTAssertEqual(result.errorMessage, ConversionError.passwordRequired.errorDescription)
    }

    func testCorruptPDFReturnsSanitizedFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpmarketCorruptPDFTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let corrupt = directory.appendingPathComponent("corrupt.pdf")
        try Data("%PDF-1.7\nnot a valid document\n%%EOF".utf8).write(to: corrupt)

        let result = await ConversionRunner().run(ConversionJob(sourceURL: corrupt))

        guard let message = result.errorMessage else {
            return XCTFail("Expected corrupt PDF conversion to fail")
        }
        XCTAssertFalse(message.lowercased().contains("python"))
        XCTAssertFalse(message.lowercased().contains("pdfkit"))
        XCTAssertFalse(message.lowercased().contains("docling"))
    }

    @MainActor
    func testCancellationDoesNotLeaveQueueWedged() async throws {
        let queue = ConversionQueue { _, progress in
            progress?(.python)
            try? await Task.sleep(nanoseconds: 200_000_000)
            return .failure(ConversionError.cancelled.errorDescription ?? "Conversion cancelled.")
        }

        let first = queue.add(URL(fileURLWithPath: "/tmp/cancel-me.bin"))
        let second = queue.add(URL(fileURLWithPath: "/tmp/next.bin"))
        queue.cancel(first)

        for _ in 0..<100 {
            if let job = queue.jobs.first(where: { $0.id == second }),
               job.result != nil,
               !job.isRunning {
                break
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertEqual(queue.jobs.first(where: { $0.id == first })?.stage, .cancelled)
        XCTAssertNotNil(queue.jobs.first(where: { $0.id == second })?.result)
    }

    func testUserFacingRuntimeErrorsDoNotExposeImplementationNames() {
        let errors: [PythonBridgeError] = [
            .helperUnavailable("missing helper"),
            .helperCrashed("signal"),
            .helperBadExit(42),
            .helperStalled,
            .invalidResponse("raw"),
            .runtimeUnavailable("raw"),
            .moduleUnavailable("raw"),
            .callFailed("raw")
        ]

        for error in errors {
            let copy = error.localizedDescription.lowercased()
            XCTAssertFalse(copy.contains("python"))
            XCTAssertFalse(copy.contains("docling"))
            XCTAssertFalse(copy.contains("pythonkit"))
            XCTAssertFalse(copy.contains("pdfium"))
        }
    }

    func testAdvancedCorpusSmokeFixtureRoutesThroughHelperWhenAvailable() async throws {
        guard Bundle.main.url(forAuxiliaryExecutable: "UpmarketRuntimeHelper") != nil else {
            throw XCTSkip("Runtime helper is not embedded in this test bundle")
        }
        let fixture = corpusFixture("docling/docling/tests/data/pdf/right_to_left_01.pdf")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("Corpus fixture is not present")
        }

        let workspace = try AppWorkspace.create(prefix: "helper-corpus-smoke")
        defer { AppWorkspace.remove(workspace) }
        let copied = try AppWorkspace.copy(fixture, into: workspace)

        let result = await PythonWorker().convert(fileURL: copied, title: "right_to_left_01", useAI: false, password: nil, workspaceURL: workspace)

        XCTAssertNotNil(result.output)
    }

    private func makeHelperScript(_ source: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpmarketRuntimeHelperTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("helper.sh")
        try source.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return url
    }

    private func corpusFixture(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("tests/corpus")
            .appendingPathComponent(relativePath)
    }
}
