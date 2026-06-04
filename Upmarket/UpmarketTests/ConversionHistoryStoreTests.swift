import XCTest
@testable import Upmarket

@MainActor
final class ConversionHistoryStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UpmarketHistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        defaultsSuiteName = "UpmarketHistoryStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        if let defaultsSuiteName {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        tempDirectory = nil
        defaults = nil
        defaultsSuiteName = nil
        try super.tearDownWithError()
    }

    func testAtomicWriteAndLoad() throws {
        let store = makeStore(loadImmediately: false)
        let output = ConversionOutput(
            markdown: "# Q3 Report\n\nRevenue was up.",
            pages: 3,
            format: "PDF",
            title: "Q3 Report",
            pipeline: .enhanced,
            selectedPathway: .enhanced
        )
        let job = ConversionJob(sourceURL: URL(fileURLWithPath: "/Users/alice/Documents/q3.pdf"))

        store.record(job: job, output: output)

        XCTAssertEqual(store.records.count, 1)
        let savedFiles = try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path)
        XCTAssertEqual(savedFiles.filter { $0.hasSuffix(".json") }.count, 1)

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.records.count, 1)
        XCTAssertEqual(reloaded.records[0].sourceDisplayName, "q3.pdf")
        XCTAssertEqual(reloaded.records[0].sourceExtension, "PDF")
        XCTAssertEqual(reloaded.records[0].pipeline, .enhanced)
        XCTAssertEqual(reloaded.records[0].selectedPathway, .enhanced)
        XCTAssertEqual(reloaded.records[0].wordCount, 5)
        XCTAssertEqual(reloaded.filteredRecords(query: "Revenue").count, 1)
        XCTAssertEqual(reloaded.filteredRecords(query: "q3.pdf").count, 1)
        XCTAssertFalse(reloaded.records[0].sourceDisplayName.contains("/Users/alice"))
    }

    func testCorruptRecordDoesNotCrashLoad() throws {
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: tempDirectory.appendingPathComponent("bad.json"))

        let store = makeStore()

        XCTAssertEqual(store.records, [])
    }

    func testClearHistoryRemovesRecords() throws {
        let store = makeStore(loadImmediately: false)
        let output = ConversionOutput(
            markdown: "saved body",
            pages: 1,
            format: "PDF",
            title: "Saved",
            pipeline: .fast,
            selectedPathway: .pdfKit
        )
        store.record(job: ConversionJob(sourceURL: URL(fileURLWithPath: "/tmp/saved.pdf")), output: output)
        XCTAssertEqual(store.records.count, 1)

        store.clear()

        XCTAssertEqual(store.records, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.path))
    }

    func testDisablingHistoryClearsRecordsAndStopsWrites() throws {
        let store = makeStore(loadImmediately: false)
        let output = ConversionOutput(
            markdown: "private body",
            pages: 1,
            format: "PDF",
            title: "Private",
            pipeline: .fast,
            selectedPathway: .pdfKit
        )
        let job = ConversionJob(sourceURL: URL(fileURLWithPath: "/tmp/private.pdf"))
        store.record(job: job, output: output)
        XCTAssertEqual(store.records.count, 1)

        store.isEnabled = false
        store.record(job: job, output: output)

        XCTAssertEqual(store.records, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.path))
    }

    private func makeStore(loadImmediately: Bool = true) -> ConversionHistoryStore {
        ConversionHistoryStore(
            directoryURL: tempDirectory,
            userDefaults: defaults,
            loadImmediately: loadImmediately
        )
    }
}
