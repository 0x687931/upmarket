import XCTest
import Darwin
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
        let helper = try packagedRuntimeHelperURL()

        let status = try await RuntimeHelperClient(executableURL: helper, livenessInterval: 15).readiness()

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
        XCTAssertEqual(result.output?.selectedPathway, .enhanced)
    }

    func testConversionCallDecodesExplicitSelectedPathway() async throws {
        let helper = try makeHelperScript("""
        #!/bin/sh
        cat >/dev/null
        printf '{"success":true,"needsPassword":false,"output":{"markdown":"# Converted","pages":1,"format":"TXT","title":"Fixture","pipeline":"fast","selectedPathway":"metadata"}}\\n'
        """)
        let client = RuntimeHelperClient(executableURL: helper, livenessInterval: 2)

        let result = try await client.convert(
            fileURL: URL(fileURLWithPath: "/tmp/input.txt"),
            title: "Fixture",
            useAI: false,
            password: nil,
            workspaceURL: URL(fileURLWithPath: "/tmp")
        )

        XCTAssertEqual(result.output?.pipeline, .fast)
        XCTAssertEqual(result.output?.selectedPathway, .metadata)
        XCTAssertEqual(result.output?.provenanceLabel, "Fast")
    }

    func testConversionCallReportsProgressEventsBeforeFinalResponse() async throws {
        let helper = try makeHelperScript("""
        #!/bin/sh
        cat >/dev/null
        printf '{"event":"progress","stage":"python","fraction":0.42,"message":"Processing"}\\n'
        printf '{"success":true,"needsPassword":false,"output":{"markdown":"# Converted","pages":1,"format":"TXT","title":"Fixture","pipeline":"enhanced"}}\\n'
        """)
        let client = RuntimeHelperClient(executableURL: helper, livenessInterval: 2)
        let recorder = ProgressRecorder()

        let result = try await client.convert(
            fileURL: URL(fileURLWithPath: "/tmp/input.txt"),
            title: "Fixture",
            useAI: false,
            password: nil,
            workspaceURL: URL(fileURLWithPath: "/tmp"),
            progress: { progress in
                recorder.append(progress)
            }
        )

        XCTAssertEqual(result.output?.markdown, "# Converted")
        XCTAssertEqual(recorder.events, [
            ConversionProgress(stage: .python, fraction: 0.42, message: "Processing")
        ])
    }

    func testMalformedProgressEventDoesNotReplaceFinalResponse() async throws {
        let helper = try makeHelperScript("""
        #!/bin/sh
        cat >/dev/null
        printf '{"event":"progress","stage":"not-a-stage","fraction":"bad"}\\n'
        printf '{"success":true,"needsPassword":false,"output":{"markdown":"# Converted","pages":1,"format":"TXT","title":"Fixture","pipeline":"enhanced"}}\\n'
        """)
        let client = RuntimeHelperClient(executableURL: helper, livenessInterval: 2)
        let recorder = ProgressRecorder()

        let result = try await client.convert(
            fileURL: URL(fileURLWithPath: "/tmp/input.txt"),
            title: "Fixture",
            useAI: false,
            password: nil,
            workspaceURL: URL(fileURLWithPath: "/tmp"),
            progress: { progress in
                recorder.append(progress)
            }
        )

        XCTAssertEqual(result.output?.markdown, "# Converted")
        XCTAssertTrue(recorder.events.isEmpty)
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

    func testCancelledHelperIsForcedToExit() async throws {
        let pidFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpmarketRuntimeHelperPID-\(UUID().uuidString)")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: pidFile)
        }
        let helper = try makeHelperScript("""
        #!/bin/sh
        printf "$$" > "\(pidFile.path)"
        cat >/dev/null
        trap '' TERM
        while :; do :; done
        """)
        let client = RuntimeHelperClient(
            executableURL: helper,
            livenessInterval: 30,
            terminationGraceInterval: 0.1
        )

        let task = Task {
            try await client.readiness()
        }
        await waitUntil {
            FileManager.default.fileExists(atPath: pidFile.path)
        }
        let pid = try pidFromFile(pidFile)

        task.cancel()
        do {
            _ = try await task.value
        } catch {
            // The exact thrown helper error is less important than the process lifetime.
        }

        await waitUntil {
            !self.isProcessRunning(pid)
        }
        XCTAssertFalse(isProcessRunning(pid))
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
        let helper = try packagedRuntimeHelperURL()
        let fixture = corpusFixture("docling/docling/tests/data/pdf/right_to_left_01.pdf")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("Corpus fixture is not present")
        }

        let workspace = try AppWorkspace.create(prefix: "helper-corpus-smoke")
        defer { AppWorkspace.remove(workspace) }
        let copied = try AppWorkspace.copy(fixture, into: workspace)
        let worker = PythonWorker(helperClient: RuntimeHelperClient(executableURL: helper, livenessInterval: 15))

        let result = await worker.convert(fileURL: copied, title: "right_to_left_01", useAI: false, password: nil, workspaceURL: workspace)

        XCTAssertNotNil(result.output)
    }

    func testPreConversionAnalysisDoesNotStartHelperForNonPDFDocuments() async throws {
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpmarketAnalysisHelperMarker-\(UUID().uuidString)")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: marker)
        }
        let helper = try makeHelperScript("""
        #!/bin/sh
        touch "\(marker.path)"
        cat >/dev/null
        printf '{"success":true,"needsPassword":false}\\n'
        """)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpmarketAnalysisTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let input = directory.appendingPathComponent("draft.docx")
        try Data("analysis should not spawn helper".utf8).write(to: input)
        let runner = ConversionRunner(
            pythonWorker: PythonWorker(helperClient: RuntimeHelperClient(executableURL: helper)),
            supportsAdvancedRuntime: true
        )

        let advice = await runner.analyse(fileURL: input)

        XCTAssertNil(advice)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testRunnerCleansWorkspaceWhenAdvancedConversionIsCancelled() async throws {
        AppWorkspace.removeStaleWorkspaces()
        let before = workspaceNames()
        let helper = try makeHelperScript("""
        #!/bin/sh
        cat >/dev/null
        sleep 5
        printf '{"success":true,"needsPassword":false,"output":{"markdown":"# Late","pages":1,"format":"DOCX","title":"Late","pipeline":"enhanced"}}\\n'
        """)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpmarketCancelledRunnerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let input = directory.appendingPathComponent("cancel-me.docx")
        try Data("slow advanced conversion".utf8).write(to: input)
        let runner = ConversionRunner(
            pythonWorker: PythonWorker(helperClient: RuntimeHelperClient(executableURL: helper, livenessInterval: 15)),
            supportsAdvancedRuntime: true
        )

        let task = Task {
            await runner.run(ConversionJob(sourceURL: input))
        }
        await waitUntil {
            self.workspaceNames() != before
        }

        task.cancel()
        let result = await task.value

        XCTAssertEqual(result.errorMessage, ConversionError.cancelled.errorDescription)
        XCTAssertEqual(workspaceNames(), before)
    }

    func testGraniteAIPreviouslyBlockedCorpusFixturesRouteThroughHelperWhenModelInstalled() async throws {
        guard DeviceCapability.shared.supportsUpmarketAI else {
            throw XCTSkip("Upmarket AI requires Apple Silicon with a visible Metal device")
        }

        let helper = try packagedRuntimeHelperURL()
        let client = RuntimeHelperClient(executableURL: helper, livenessInterval: 240)
        let models = try await client.checkModels()
        guard models.contains(where: { $0.key == "upmarket_ai" && $0.isDownloaded }) else {
            throw XCTSkip("Upmarket AI model is not installed in Application Support")
        }

        let fixtures = [
            "docling/docling/tests/data/latex/1706.03762/Figures/ModalNet-32.png",
            "docling/docling/tests/data/latex/2310.06825/images/230927_effective_sizes.png",
            "docling/docling/tests/data/latex/2310.06825/images/llama_vs_mistral_example.png",
            "docling/docling/tests/data/tiff/2206.01062.tif",
        ]

        for relativePath in fixtures {
            let fixture = corpusFixture(relativePath)
            guard FileManager.default.fileExists(atPath: fixture.path) else {
                throw XCTSkip("Corpus fixture is not present: \(relativePath)")
            }

            let workspace = try AppWorkspace.create(prefix: "helper-granite-ai-smoke")
            defer { AppWorkspace.remove(workspace) }
            let copied = try AppWorkspace.copy(fixture, into: workspace)
            let result: ConversionResult
            do {
                result = try await client.convert(
                    fileURL: copied,
                    title: copied.deletingPathExtension().lastPathComponent,
                    useAI: true,
                    password: nil,
                    workspaceURL: workspace
                )
            } catch let error as PythonBridgeError {
                if error.diagnosticCode == "runtime.helper.runtime-unavailable" {
                    throw XCTSkip("Granite AI model is installed, but this Xcode session cannot access Metal: \(error)")
                }
                return XCTFail("Expected Granite AI output for \(relativePath), got \(error.diagnosticCode): \(error)")
            } catch {
                return XCTFail("Expected Granite AI output for \(relativePath), got: \(error)")
            }

            guard let output = result.output else {
                return XCTFail("Expected Granite AI output for \(relativePath), got conversion failure: \(result.errorMessage ?? "nil")")
            }
            XCTAssertEqual(output.pipeline, .ai)
            XCTAssertFalse(output.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    func testRuntimeHelperForwardsOnlyExplicitAITestDoubleEnvironment() async throws {
        setenv("UPMARKET_ENABLE_TEST_DOUBLES", "1", 1)
        setenv("UPMARKET_TEST_UPMARKET_AI_RUNTIME", "unavailable", 1)
        setenv("UPMARKET_SECRET_SHOULD_NOT_PASS", "secret", 1)
        defer {
            unsetenv("UPMARKET_ENABLE_TEST_DOUBLES")
            unsetenv("UPMARKET_TEST_UPMARKET_AI_RUNTIME")
            unsetenv("UPMARKET_SECRET_SHOULD_NOT_PASS")
        }

        let helper = try makeHelperScript("""
        #!/bin/sh
        cat >/dev/null
        if [ "$UPMARKET_ENABLE_TEST_DOUBLES" = "1" ] \\
          && [ "$UPMARKET_TEST_UPMARKET_AI_RUNTIME" = "unavailable" ] \\
          && [ -z "$UPMARKET_SECRET_SHOULD_NOT_PASS" ]; then
          printf '{"success":true,"needsPassword":false,"version":"test-env"}\\n'
        else
          printf '{"success":false,"code":"runtime.helper.invalid-response","message":"unexpected environment","needsPassword":false}\\n'
        fi
        """)

        let client = RuntimeHelperClient(executableURL: helper)
        let status = try await client.readiness()
        XCTAssertTrue(status.isReady)
        XCTAssertEqual(status.version, "test-env")
    }

    func testLegacyHelperModelDownloadIsDeveloperOnly() async throws {
        let previous = getenv("UPMARKET_ENABLE_DEVELOPER_MODEL_INTAKE").map { String(cString: $0) }
        unsetenv("UPMARKET_ENABLE_DEVELOPER_MODEL_INTAKE")
        defer {
            if let previous {
                setenv("UPMARKET_ENABLE_DEVELOPER_MODEL_INTAKE", previous, 1)
            } else {
                unsetenv("UPMARKET_ENABLE_DEVELOPER_MODEL_INTAKE")
            }
        }

        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpmarketDeveloperModelIntakeMarker-\(UUID().uuidString)")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: marker)
        }
        let helper = try makeHelperScript("""
        #!/bin/sh
        touch "\(marker.path)"
        cat >/dev/null
        printf '{"success":true,"needsPassword":false}\\n'
        """)
        let client = RuntimeHelperClient(executableURL: helper)
        let progressFile = marker.deletingLastPathComponent()
            .appendingPathComponent("upmarket_download_progress.jsonl")

        let result = await client.downloadModel(
            key: "upmarket_ai",
            progressFile: progressFile.path,
            workspaceURL: FileManager.default.temporaryDirectory
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.error, "Developer model intake is disabled for this build.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    func testPackagedRuntimeHelperAITestDoublesCoverAvailableAndUnavailableRuntime() async throws {
        let helper = try packagedRuntimeHelperURL()
        let client = RuntimeHelperClient(executableURL: helper, livenessInterval: 30)
        let inputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpmarketAITestDoubleInputs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: inputDirectory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: inputDirectory)
        }

        let input = inputDirectory.appendingPathComponent("sample.png")
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC")!
        try png.write(to: input)

        setenv("UPMARKET_ENABLE_TEST_DOUBLES", "1", 1)
        setenv("UPMARKET_TEST_UPMARKET_AI_HARDWARE", "available", 1)
        setenv("UPMARKET_TEST_UPMARKET_AI_CONVERTER", "stub", 1)
        defer {
            unsetenv("UPMARKET_ENABLE_TEST_DOUBLES")
            unsetenv("UPMARKET_TEST_UPMARKET_AI_HARDWARE")
            unsetenv("UPMARKET_TEST_UPMARKET_AI_RUNTIME")
            unsetenv("UPMARKET_TEST_UPMARKET_AI_CONVERTER")
        }

        setenv("UPMARKET_TEST_UPMARKET_AI_RUNTIME", "unavailable", 1)
        let unavailableWorkspace = try AppWorkspace.create(prefix: "helper-ai-runtime-unavailable")
        defer { AppWorkspace.remove(unavailableWorkspace) }
        let unavailableCopy = try AppWorkspace.copy(input, into: unavailableWorkspace)
        do {
            _ = try await client.convert(
                fileURL: unavailableCopy,
                title: unavailableCopy.deletingPathExtension().lastPathComponent,
                useAI: true,
                password: nil,
                workspaceURL: unavailableWorkspace
            )
            XCTFail("Expected runtime-unavailable error for forced non-Metal runtime")
        } catch let error as PythonBridgeError {
            XCTAssertEqual(error.diagnosticCode, "runtime.helper.runtime-unavailable")
        }

        setenv("UPMARKET_TEST_UPMARKET_AI_RUNTIME", "available", 1)
        let availableWorkspace = try AppWorkspace.create(prefix: "helper-ai-runtime-available")
        defer { AppWorkspace.remove(availableWorkspace) }
        let availableCopy = try AppWorkspace.copy(input, into: availableWorkspace)
        let result = try await client.convert(
            fileURL: availableCopy,
            title: availableCopy.deletingPathExtension().lastPathComponent,
            useAI: true,
            password: nil,
            workspaceURL: availableWorkspace
        )
        let output = try XCTUnwrap(result.output)
        XCTAssertEqual(output.pipeline, .ai)
        XCTAssertTrue(output.markdown.contains("test-double conversion succeeded"))
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

    private func packagedRuntimeHelperURL() throws -> URL {
        let helper = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/UpmarketRuntimeHelper")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw XCTSkip("App-packaged runtime helper is not embedded in the test host")
        }
        XCTAssertTrue(helper.path.contains(".app/Contents/MacOS/UpmarketRuntimeHelper"))
        XCTAssertFalse(helper.path.hasSuffix("/Build/Products/Debug/UpmarketRuntimeHelper"))
        return helper
    }

    private func corpusFixture(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("tests/corpus")
            .appendingPathComponent(relativePath)
    }

    private func waitUntil(_ predicate: @escaping () -> Bool) async {
        for _ in 0..<100 {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for condition")
    }

    private func workspaceNames() -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: AppWorkspace.baseDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        return entries.map(\.lastPathComponent).sorted()
    }

    private func pidFromFile(_ url: URL) throws -> pid_t {
        let raw = try String(contentsOf: url, encoding: .utf8)
        guard let pid = Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw NSError(domain: "UpmarketTests", code: 1)
        }
        return pid
    }

    private func isProcessRunning(_ pid: pid_t) -> Bool {
        Darwin.kill(pid, 0) == 0
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [ConversionProgress] = []

    var events: [ConversionProgress] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func append(_ progress: ConversionProgress) {
        lock.lock()
        stored.append(progress)
        lock.unlock()
    }
}
