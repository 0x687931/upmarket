# Apple API Improvements Implementation Plan

## Overview
Four complementary improvements to fully leverage Apple's Vision and recognition APIs:
1. Document splitting for Vision page limits
2. Document type (ElementType) extraction and metadata
3. Enhanced OCR with handwriting detection
4. Table structure preservation and repair

---

## 1. Document Splitting for Vision (Page Limit: ~20-30)

**Problem:** VisionDocumentExtractor fails on PDFs > ~20 pages with `tooManyPages` error

**Solution:** Split large PDFs into Vision-safe chunks before processing

### Files to Create
- `Upmarket/Services/DocumentChunker.swift` (new)

### Architecture
```swift
struct DocumentChunker {
    /// Split PDF into chunks suitable for Vision processing
    static func chunk(pdfURL: URL, maxPages: Int = 20) throws -> [ChunkedDocument]
    
    struct ChunkedDocument {
        let pages: [PDFPage]
        let startIndex: Int
        let endIndex: Int
        let isLast: Bool
    }
}
```

### Integration Points
- **VisionDocumentExtractor.extractStructured():** Check page count, chunk if needed
- **ConversionRunner.run():** Choose Vision or fallback based on page count

### Effort: **LOW** (~100 LOC)

---

## 2. DocumentObservation.ElementType Extraction

**Problem:** Apple exposes document semantic type (form, receipt, invoice) but we discard it

**Solution:** Extract elementType and preserve as document metadata

### Files to Modify
- `ConversionOutput.swift` — Add metadata field
- `VisionDocumentExtractor.swift` — Extract elementType
- `DocumentMetadata.swift` (new) — Define metadata structure

### Architecture
```swift
struct DocumentMetadata: Codable, Equatable, Sendable {
    let elementType: String?  // form, receipt, invoice, document, etc.
    let language: String?
    let extractionMethod: String  // "pdfkit", "vision", "docling"
    let extractionConfidence: Double
    let containsHandwriting: Bool
}

struct ConversionOutput: Equatable, Sendable {
    let markdown: String
    let pages: Int
    let format: String
    let title: String
    let pipeline: Pipeline
    let selectedPathway: ConversionPathway
    let metadata: DocumentMetadata  // NEW
}
```

### Implementation
```swift
@available(macOS 26, *)
private static func extractMetadata(doc: DocumentObservation) -> DocumentMetadata {
    let elementType: String? = doc.elementType?.rawValue
    return DocumentMetadata(
        elementType: elementType,
        language: nil,
        extractionMethod: "vision",
        extractionConfidence: 0.85,
        containsHandwriting: false  // Will be enhanced in step 3
    )
}
```

### Effort: **LOW-MEDIUM** (~150 LOC)

---

## 3. Enhanced VNRecognizeTextRequest for OCR

**Problem:** We don't check for handwriting or use full capabilities of VNRecognizeTextRequest

**Solution:** Detect handwriting and optimize routing

### Files to Modify
- `VisionOCR.swift` — Check handwriting flag
- `NativeDocumentClassifier.swift` — Add handwriting evidence
- `ConversionRunner.swift` — Route based on handwriting

### Architecture
```swift
struct VisionPageInspection {
    let observedTextLines: Int
    let averageConfidence: Float
    // ... existing fields ...
    let handwritingConfidence: Float  // NEW
    let estimatedHandwritingRatio: Double  // NEW
}

struct NativeDocumentClassifier.Evidence {
    // ... existing fields ...
    let hasSignificantHandwriting: Bool  // NEW
}
```

### Implementation in VisionOCR
```swift
private static func inspectTextAndLayout(in image: CGImage) async -> VisionPageInspection {
    let textRequest = VNRecognizeTextRequest()
    textRequest.recognitionLevel = .fast
    textRequest.usesLanguageCorrection = false
    
    // Check handwriting if available (macOS 13+)
    if #available(macOS 13, *) {
        textRequest.automaticallyDetectsLanguage = true
    }
    
    // Process and check results for handwriting confidence
    var handwritingConfidence: Float = 0
    let observations = textRequest.results ?? []
    for obs in observations {
        if let topCandidate = obs.topCandidates(1).first {
            // Check if marked as handwriting (if API exposes it)
            handwritingConfidence = max(handwritingConfidence, topCandidate.confidence)
        }
    }
    
    return VisionPageInspection(
        // ... existing fields ...
        handwritingConfidence: handwritingConfidence,
        estimatedHandwritingRatio: /* calculate from results */
    )
}
```

### Effort: **MEDIUM** (~200 LOC)

---

## 4. TableRepair Integration (HIGH VALUE)

**Problem:** Tables detected by Vision but lost during conversion; no auto-repair capability

**Solution:** Thread StructuredTable through entire pipeline

### Files to Modify
1. **ConversionOutput.swift** — Add originalTables field
2. **VisionDocumentExtractor.swift** — Extract and preserve StructuredTable
3. **DocumentStructureValidator.swift** — Compare and use for repair
4. **ConversionPostProcessor.swift** — Call TableRepair
5. **ConversionRunner.swift** — Pass tables through result

### Step 1: Modify ConversionOutput
```swift
nonisolated struct ConversionOutput: Equatable, Sendable {
    let markdown: String
    let pages: Int
    let format: String
    let title: String
    let pipeline: Pipeline
    let selectedPathway: ConversionPathway
    let metadata: DocumentMetadata
    let originalTables: [TableRepair.StructuredTable]  // NEW
    
    init(
        markdown: String,
        pages: Int,
        format: String,
        title: String,
        pipeline: Pipeline,
        selectedPathway: ConversionPathway? = nil,
        metadata: DocumentMetadata = .default,
        originalTables: [TableRepair.StructuredTable] = []  // NEW
    ) { ... }
}
```

### Step 2: Modify VisionDocumentExtractor
```swift
@available(macOS 26, *)
private static func extractStructuredTables(doc: DocumentObservation) -> [TableRepair.StructuredTable] {
    var tables: [TableRepair.StructuredTable] = []
    
    for visionTable in doc.tables {
        var rows: [[String]] = []
        
        for row in visionTable.rows {
            var cellStrings: [String] = []
            for cell in row {
                let content = textFromContainerBox(cell.content)
                cellStrings.append(content)
            }
            rows.append(cellStrings)
        }
        
        tables.append(TableRepair.StructuredTable(rows: rows))
    }
    
    return tables
}

// In processImage():
let tables = extractStructuredTables(doc: doc)  // NEW
// Return tables alongside markdown
```

### Step 3: Modify DocumentStructureValidator
```swift
static func validateAndRepair(
    originalMarkdown: String,
    convertedMarkdown: String,
    originalTables: [TableRepair.StructuredTable] = []  // NEW
) -> ValidationReport {
    // ... existing validation ...
    
    // NEW: Check for missing tables and repair
    let missingTables = TableRepair.detectMissingTables(
        originalTables: originalTables,
        outputMarkdown: convertedMarkdown
    )
    
    var repaired = convertedMarkdown
    if !missingTables.isEmpty {
        repaired = TableRepair.repairMissingTables(
            markdown: convertedMarkdown,
            insertTables: missingTables
        )
    }
    
    return ValidationReport(
        // ... existing fields ...
        reformattedMarkdown: repaired
    )
}
```

### Step 4: Modify ConversionPostProcessor
```swift
static func process(_ output: ConversionOutput) async -> ConversionOutput {
    // ... existing code ...
    
    // Validate structure with table repair capability
    let structureReport = DocumentStructureValidator.validateAndRepair(
        originalMarkdown: originalMarkdown,
        convertedMarkdown: finalMarkdown,
        originalTables: output.originalTables  // NEW
    )
    
    if let repairedMarkdown = structureReport.reformattedMarkdown {
        finalMarkdown = repairedMarkdown
    }
    
    // Return with preserved tables
    return ConversionOutput(
        markdown: finalMarkdown,
        pages: output.pages,
        format: output.format,
        title: title,
        pipeline: output.pipeline,
        selectedPathway: output.selectedPathway,
        metadata: output.metadata,  // NEW
        originalTables: output.originalTables  // NEW
    )
}
```

### Effort: **MEDIUM** (~300 LOC, but straightforward threading)

---

## Implementation Sequence

### Phase 1: Foundation (Can be done in parallel)
1. Create DocumentMetadata structure
2. Create DocumentChunker for Vision page limits
3. Run tests to ensure no regressions

### Phase 2: Metadata & Detection
1. Modify ConversionOutput to include metadata
2. Extract DocumentObservation.elementType in VisionDocumentExtractor
3. Enhance VNRecognizeTextRequest with handwriting detection
4. Test on sample PDFs

### Phase 3: Table Integration (High Value)
1. Modify ConversionOutput to include originalTables
2. Extract StructuredTable in VisionDocumentExtractor
3. Modify DocumentStructureValidator to use tables
4. Integrate TableRepair in ConversionPostProcessor
5. Comprehensive testing on invoices, forms, complex PDFs

---

## Testing Strategy

### Unit Tests
- DocumentChunker: Split PDFs, verify chunk boundaries
- DocumentMetadata: Serialization, equality
- VisionDocumentExtractor: Table extraction, metadata
- TableRepair: Detection, insertion, formatting

### Integration Tests
- GST Invoice (95 pages) → chunks to Vision
- Tax Return (18 pages) → Vision extraction with tables
- Academic Paper (393 pages) → chunks, validates
- End-to-end: Conversion → Validation → Repair

### Regression Tests
- Existing PDFKit pathway unchanged
- Existing Docling pathway unchanged
- All existing tests pass

---

## Risk Mitigation

| Risk | Mitigation |
| --- | --- |
| Breaking PDFKit pathway | Keep existing code unchanged, add parallel Vision path |
| Page limit edge cases | Comprehensive chunking tests with 20, 30, 31 page PDFs |
| Table threading errors | Add optional originalTables, default to empty |
| Metadata serialization | Use Codable, test encoding/decoding |

---

## Success Criteria

✅ Large PDFs (>30 pages) can be chunked and processed by Vision
✅ DocumentObservation.elementType extracted and preserved
✅ Handwriting detected and routed appropriately
✅ Missing tables auto-repaired from Vision data
✅ All existing tests pass
✅ Zero regressions in conversion quality
