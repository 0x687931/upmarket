import XCTest
import PDFKit
@testable import Upmarket

/// Tests the complete validation and repair pipeline on real PDFs
final class PDFValidationPipelineTests: XCTestCase {

    let testPDFs = [
        (
            path: "/Users/am/Downloads/gst_Web_1e92db95-a75c-4f4e-a3d4-39f43b1a3b25.pdf",
            name: "GST Invoice",
            expectedType: "receipt or invoice"
        ),
        (
            path: "/Users/am/Downloads/409787_TaxReturn_4.pdf",
            name: "Tax Return (Structured Form)",
            expectedType: "structured form"
        ),
        (
            path: "/Users/am/Downloads/IndiaMathPapersRamanujan.pdf",
            name: "Academic Paper",
            expectedType: "academic document"
        )
    ]

    /// Test: Verify document classification handles different document types
    @MainActor
    func testDocumentClassificationOnRealPDFs() async throws {
        for (path, name, expectedType) in testPDFs {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else {
                print("⏭️  Skipping \(name) - PDF not found at \(path)")
                continue
            }

            print("\n=== Classifying: \(name) ===")

            let classification = try await NativeDocumentClassifier.classify(pdfURL: url)

            print("Recommended pathway: \(classification.recommendedPathway.diagnosticLabel)")
            print("Confidence: \(Int(classification.confidence * 100))%")
            print("Bucket: \(classification.bucket.diagnosticLabel)")
            print("Reasons: \(classification.reasons.joined(separator: ", "))")
            print("Expected: \(expectedType)")
        }
    }

    /// Test: Run PDFs through native extraction and validate structure
    @MainActor
    func testPDFExtractionAndStructureValidation() async throws {
        for (path, name, _) in testPDFs {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else {
                print("⏭️  Skipping \(name) - PDF not found at \(path)")
                continue
            }

            print("\n=== Processing with PDFKit: \(name) ===")

            // Extract with PDFKit
            guard let pdfDoc = PDFDocument(url: url) else {
                print("❌ Could not open PDF")
                continue
            }

            var markdown = ""
            let pageCount = pdfDoc.pageCount

            // Extract text from PDF
            for i in 0..<min(pageCount, 3) {  // Sample first 3 pages for speed
                if let page = pdfDoc.page(at: i), let text = page.string {
                    markdown += "## Page \(i + 1)\n\n\(text)\n\n"
                }
            }

            if markdown.isEmpty {
                print("⚠️  No text extracted (likely scanned)")
                continue
            }

            // Validate structure
            let report = DocumentStructureValidator.validateAndRepair(
                originalMarkdown: markdown,
                convertedMarkdown: markdown
            )

            print("Pages processed: \(pageCount)")
            print("Structure valid: \(report.isValid)")
            print("Heading count: \(report.metrics.inputHeadingCount)")
            print("Table count: \(report.metrics.inputTableCount)")
            print("List count: \(report.metrics.inputListCount)")
            print("Structure retention: \(Int(report.metrics.structureRetention * 100))%")

            if !report.isValid {
                print("Issues found:")
                for issue in report.issues {
                    let severity = issue.severity == .error ? "❌ ERROR" : "⚠️  WARNING"
                    print("  \(severity): \(issue.description)")
                }
            }

            if report.reformattedMarkdown != nil {
                print("✅ Auto-repaired markdown")
            }
        }
    }

    /// Test: Vision Document Extractor for structure detection (macOS 26+)
    @MainActor
    func testVisionDocumentExtractionIfAvailable() async throws {
        guard VisionDocumentExtractor.isAvailable else {
            print("⏭️  VisionDocumentExtractor requires macOS 26+, skipping")
            return
        }

        for (path, name, _) in testPDFs {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else {
                print("⏭️  Skipping \(name) - PDF not found at \(path)")
                continue
            }

            print("\n=== Vision Document Extractor: \(name) ===")

            do {
                let result = try await VisionDocumentExtractor.extract(pdfURL: url)
                print("✅ Extraction successful")
                print("Pages: \(result.pageCount)")
                print("Tables detected: \(result.tablesFound)")
                print("Lists detected: \(result.listsFound)")
                print("Used structured API: \(result.usedStructuredAPI)")
                print("Markdown length: \(result.markdown.count) chars")

                // Validate the extracted markdown
                let report = DocumentStructureValidator.validateAndRepair(
                    originalMarkdown: result.markdown,
                    convertedMarkdown: result.markdown
                )
                print("Headings in output: \(report.metrics.outputHeadingCount)")
                print("Tables in output: \(report.metrics.outputTableCount)")
            } catch {
                print("❌ Extraction failed: \(error)")
            }
        }
    }

    /// Test: Full conversion pipeline simulation
    @MainActor
    func testFullConversionPipeline() async throws {
        for (path, name, _) in testPDFs {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else {
                print("⏭️  Skipping \(name) - PDF not found at \(path)")
                continue
            }

            print("\n=== Full Pipeline: \(name) ===")

            // Step 1: Extract markdown (simulating native pathway)
            guard let pdfDoc = PDFDocument(url: url) else {
                print("❌ Could not open PDF")
                continue
            }

            var markdown = ""
            for i in 0..<min(pdfDoc.pageCount, 3) {
                if let page = pdfDoc.page(at: i), let text = page.string {
                    markdown += text + "\n\n"
                }
            }

            if markdown.isEmpty {
                print("⚠️  No extractable text (scanned document)")
                continue
            }

            // Step 2: Create conversion output
            var output = ConversionOutput(
                markdown: markdown,
                pages: pdfDoc.pageCount,
                format: "PDF",
                title: name,
                pipeline: .fast
            )

            // Step 3: Run through post-processor (includes validation/repair)
            output = await ConversionPostProcessor.process(output)

            print("✅ Conversion complete")
            print("Final markdown length: \(output.markdown.count) chars")
            print("Title: \(output.title)")

            // Analyze what changed
            let originalLines = markdown.components(separatedBy: .newlines).count
            let finalLines = output.markdown.components(separatedBy: .newlines).count

            if finalLines != originalLines {
                print("📊 Structure modified: \(originalLines) → \(finalLines) lines")
            }
        }
    }
}
