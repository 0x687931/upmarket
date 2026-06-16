import XCTest
@testable import Upmarket

final class NativeEPUBConverterTests: XCTestCase {

    // MARK: - OPF parsing (pure functions)

    func testOPFPathReadFromContainer() {
        let container = Data("""
        <?xml version="1.0"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """.utf8)
        XCTAssertEqual(NativeEPUBConverter.opfPath(fromContainer: container), "OEBPS/content.opf")
    }

    func testSpineOrderResolvesRelativeHrefsAndSkipsNonContent() {
        let opf = Data("""
        <?xml version="1.0"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <manifest>
            <item id="cover" href="cover.xhtml" media-type="application/xhtml+xml"/>
            <item id="ch1" href="text/chapter1.xhtml" media-type="application/xhtml+xml"/>
            <item id="ch2" href="text/chapter2.xhtml" media-type="application/xhtml+xml"/>
            <item id="css" href="style.css" media-type="text/css"/>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
            <itemref idref="ch2"/>
            <itemref idref="cover"/>
          </spine>
        </package>
        """.utf8)
        // Reading order from the spine, resolved relative to the OPF dir; CSS excluded.
        let paths = NativeEPUBConverter.orderedContentPaths(opfXML: opf, opfPath: "OEBPS/content.opf")
        XCTAssertEqual(paths, [
            "OEBPS/text/chapter1.xhtml",
            "OEBPS/text/chapter2.xhtml",
            "OEBPS/cover.xhtml",
        ])
    }

    func testHrefFragmentsAndPercentEncodingAndDotSegmentsAreNormalized() {
        let opf = Data("""
        <package xmlns="http://www.idpf.org/2007/opf">
          <manifest>
            <item id="a" href="../Text/Chapter%20One.xhtml#start" media-type="application/xhtml+xml"/>
          </manifest>
          <spine><itemref idref="a"/></spine>
        </package>
        """.utf8)
        let paths = NativeEPUBConverter.orderedContentPaths(opfXML: opf, opfPath: "OEBPS/content.opf")
        XCTAssertEqual(paths, ["Text/Chapter One.xhtml"])
    }

    // MARK: - End-to-end conversion

    func testConvertsMinimalEPUBInSpineOrder() throws {
        let chapter1 = "<html><body><h1>First</h1><p>Alpha body.</p></body></html>"
        let chapter2 = "<html><body><h1>Second</h1><p>Beta body.</p></body></html>"
        let container = """
        <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        <rootfiles><rootfile full-path="content.opf"/></rootfiles></container>
        """
        let opf = """
        <package xmlns="http://www.idpf.org/2007/opf">
        <manifest>
        <item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>
        <item id="c2" href="c2.xhtml" media-type="application/xhtml+xml"/>
        </manifest>
        <spine><itemref idref="c1"/><itemref idref="c2"/></spine>
        </package>
        """
        let zip = Self.makeStoredZip([
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", Data(container.utf8)),
            ("content.opf", Data(opf.utf8)),
            ("c1.xhtml", Data(chapter1.utf8)),
            ("c2.xhtml", Data(chapter2.utf8)),
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("epub-\(UUID().uuidString).epub")
        try zip.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let markdown = try NativeEPUBConverter.convert(fileURL: url)
        XCTAssertTrue(markdown.contains("First"), markdown)
        XCTAssertTrue(markdown.contains("Second"), markdown)
        // Reading order preserved: chapter 1 before chapter 2.
        let firstRange = try XCTUnwrap(markdown.range(of: "First"))
        let secondRange = try XCTUnwrap(markdown.range(of: "Second"))
        XCTAssertLessThan(firstRange.lowerBound, secondRange.lowerBound)
    }

    // MARK: - Minimal STORED-method (method 0) ZIP writer for tests

    private static func makeStoredZip(_ entries: [(name: String, data: Data)]) -> Data {
        var output = Data()
        var central = Data()
        var offsets: [Int] = []

        func u16(_ v: Int) -> Data { var x = UInt16(v).littleEndian; return Data(bytes: &x, count: 2) }
        func u32(_ v: Int) -> Data { var x = UInt32(v).littleEndian; return Data(bytes: &x, count: 4) }

        for entry in entries {
            let name = Data(entry.name.utf8)
            offsets.append(output.count)
            // Local file header (no compression, CRC unused by ZipReader).
            output.append(u32(0x0403_4b50))
            output.append(u16(20))            // version needed
            output.append(u16(0))             // flags
            output.append(u16(0))             // method = stored
            output.append(u16(0)); output.append(u16(0)) // mod time/date
            output.append(u32(0))             // crc32 (unchecked)
            output.append(u32(entry.data.count)) // compressed size
            output.append(u32(entry.data.count)) // uncompressed size
            output.append(u16(name.count))    // name length
            output.append(u16(0))             // extra length
            output.append(name)
            output.append(entry.data)
        }

        for (index, entry) in entries.enumerated() {
            let name = Data(entry.name.utf8)
            central.append(u32(0x0201_4b50))
            central.append(u16(20)); central.append(u16(20)) // version made/needed
            central.append(u16(0))            // flags
            central.append(u16(0))            // method = stored
            central.append(u16(0)); central.append(u16(0)) // mod time/date
            central.append(u32(0))            // crc32
            central.append(u32(entry.data.count)) // compressed size
            central.append(u32(entry.data.count)) // uncompressed size
            central.append(u16(name.count))   // name length
            central.append(u16(0)); central.append(u16(0)) // extra/comment length
            central.append(u16(0)); central.append(u16(0)) // disk start / internal attrs
            central.append(u32(0))            // external attrs
            central.append(u32(offsets[index])) // local header offset
            central.append(name)
        }

        let cdOffset = output.count
        output.append(central)
        // End of central directory.
        output.append(u32(0x0605_4b50))
        output.append(u16(0)); output.append(u16(0)) // disk numbers
        output.append(u16(entries.count)); output.append(u16(entries.count))
        output.append(u32(central.count))
        output.append(u32(cdOffset))
        output.append(u16(0))                 // comment length
        return output
    }
}
