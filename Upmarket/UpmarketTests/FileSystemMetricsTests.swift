import XCTest
@testable import Upmarket

final class FileSystemMetricsTests: XCTestCase {
    func testFileSizeReaderRefreshesChangedFile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("document.pdf")

        try Data(repeating: 1, count: 7).write(to: file)
        let initialSize = await FileSystemMetrics.shared.readFileSize(file)
        XCTAssertEqual(initialSize, 7)

        try Data(repeating: 2, count: 19).write(to: file)
        await FileSystemMetrics.shared.invalidate(file)
        let changedSize = await FileSystemMetrics.shared.readFileSize(file)
        XCTAssertEqual(changedSize, 19)
    }

    func testDirectorySizeReaderSumsNestedFiles() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let nested = directory.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 11).write(to: directory.appendingPathComponent("one.bin"))
        try Data(repeating: 2, count: 17).write(to: nested.appendingPathComponent("two.bin"))

        await FileSystemMetrics.shared.invalidate(directory)
        let size = await FileSystemMetrics.shared.readDirectorySize(directory)
        XCTAssertEqual(size, 28)
    }

    func testSignatureReaderSeparatesFolderIdentityAndDetectsChanges() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("incoming.pdf")
        let firstFolderID = UUID()
        let secondFolderID = UUID()

        try Data(repeating: 1, count: 5).write(to: file)
        let first = await FileSystemMetrics.shared.getFileSignature(for: file, folderID: firstFolderID)
        let secondFolder = await FileSystemMetrics.shared.getFileSignature(for: file, folderID: secondFolderID)

        XCTAssertEqual(first?.size, 5)
        XCTAssertEqual(first?.folderID, firstFolderID)
        XCTAssertEqual(secondFolder?.folderID, secondFolderID)

        try Data(repeating: 2, count: 13).write(to: file)
        await FileSystemMetrics.shared.invalidate(file)
        let changed = await FileSystemMetrics.shared.getFileSignature(for: file, folderID: firstFolderID)
        XCTAssertEqual(changed?.size, 13)
        XCTAssertNotEqual(changed, first)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileSystemMetricsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
