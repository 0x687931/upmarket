# Apple APIs Inventory: What We Use & What We're Missing

## Currently Leveraged APIs

### ✅ Vision Framework
- **RecognizeDocumentsRequest** (macOS 26+)
  - Document structure extraction
  - Table detection with structure
  - List detection
  - Title/heading extraction
  - ✅ Implemented in VisionDocumentExtractor

- **VNRecognizeTextRequest** (macOS 10.15+)
  - Optical Character Recognition
  - Text recognition on images/PDFs
  - ✅ Implemented in VisionOCR

### ✅ PDFKit
- **PDFDocument** — Read PDF files
- **PDFPage** — Extract pages
- **PDFSelection** — Text extraction
- ✅ Implemented in PDFConverter, VisionOCR

### ✅ NaturalLanguage Framework
- **NLLanguageRecognizer** — Language detection
- ✅ Implemented in DocumentIntelligence

### ✅ Speech Framework
- **SFSpeechRecognizer** — Audio transcription
- ✅ Implemented in SpeechTranscriber

### ✅ AVFoundation
- **AVAsset** — Audio/video metadata
- ✅ Implemented in NativeMetadataExtractor

### ✅ OSLog
- **Logger** — Structured logging
- ✅ Implemented throughout (diagnostics, validation)

---

## Partially Leveraged APIs

### ⚠️ Foundation Models (macOS 26+)
- **LanguageModelSession** — On-device AI inference
- **@Generable/@Guide** — Structured generation
- Status: Scaffolding exists, actual implementation deferred
- Missing: Wire FoundationModelsImpl to FoundationModelEnhancer

### ⚠️ Vision Framework — Advanced Features
- **RecognizeDocumentsRequest extras:**
  - Document classification (form, receipt, invoice, etc.)
  - Barcode detection
  - Text reading with languages
- Status: Basic extraction working, advanced features untouched

---

## High-Priority Missing APIs

### 🔴 Table Structure (Apple exposes, we don't use)

```swift
DocumentObservation.Container.Table {
    rows: [Row]              // ← We extract but don't preserve
}

// Currently: Convert to markdown immediately, lose structure
// Should: Preserve StructuredTable objects, repair missing tables
```

**Status:** TableRepair module ready, needs pipeline integration
**Priority:** HIGH (already extracted, just need to preserve & use)

### 🔴 Document Classification (Apple exposes, we don't use)

```swift
DocumentObservation.ElementType  // Enum: form, receipt, invoice, etc.
```

**Use case:** Route processing differently for receipts vs. invoices
**Priority:** MEDIUM (useful but can work without it)

### 🔴 Handwriting Recognition (Apple exposes, we ignore)

```swift
VNRecognizeTextRequest supports:
- handwriting recognition
- real-time character boxes
```

**Current:** Only handles printed text
**Potential:** Better scanned document handling
**Priority:** MEDIUM (most PDFs are printed, not handwritten)

### 🔴 Form Field Detection (Apple exposes, we don't use)

```swift
DocumentObservation might expose:
- Form fields (text input, checkbox, etc.)
- Field boundaries
- Required fields
```

**Use case:** Convert fillable PDFs to markdown with field markers
**Priority:** LOW (specialized use case)

---

## Emerging/Future APIs We Don't Use Yet

### 🟡 Machine Readable Zone (MRZ) Parsing

```swift
// Not yet: Passport, ID card text extraction
// Apple may expose in future Vision update
```

**Use case:** Extract ID document metadata
**Priority:** LOW (specialized)

### 🟡 Barcode/QR Code Extraction

```swift
// Not yet: Extract data from barcodes
// Apple exposes in Vision, we don't use
```

**Use case:** Extract tracking numbers, product codes
**Priority:** LOW (specialized)

### 🟡 Signature Detection

```swift
// Not yet: Detect signatures vs text
// Could be useful for contract documents
```

**Use case:** Mark signature areas in markdown
**Priority:** LOW (specialized)

---

## APIs We Intentionally Don't Use

### ❌ CloudKit (No cloud processing)
- Philosophy: 100% offline, no server-side processing
- Correct decision ✓

### ❌ Network APIs for model download (Custom implementation)
- Reason: Using BackgroundAssetsDownloadService (more control)
- Correct decision ✓

### ❌ Objective-C Runtime (Pure Swift)
- Reason: Cleaner, type-safe
- Correct decision ✓

---

## Recommended Next Steps (By Priority)

### PRIORITY 1: Preserve Table Structure
**Effort:** Medium | **Impact:** HIGH
```
1. Modify VisionDocumentExtractor to keep StructuredTable objects
2. Thread through ConversionOutput
3. Use TableRepair to reconstruct missing tables
→ Automatically recover missing tables from Vision data
```

### PRIORITY 2: Document Classification
**Effort:** Low | **Impact:** MEDIUM
```
1. Extract document type from RecognizeDocumentsRequest
2. Route to specialized processing (receipt, invoice, form)
3. Apply format-specific validation
→ Better handling of specialized documents
```

### PRIORITY 3: Handwriting Detection
**Effort:** Medium | **Impact:** MEDIUM
```
1. Check VNRecognizeTextRequest language/script
2. Flag if handwritten detected
3. Apply special OCR or user warning
→ Better scanned document quality
```

### PRIORITY 4: Form Field Detection
**Effort:** High | **Impact:** LOW
```
1. Extract form fields from DocumentObservation
2. Represent as markdown code blocks or markers
3. Preserve field structure
→ Better fillable PDF handling (niche use case)
```

---

## Current Coverage Matrix

| Apple API | Framework | We Use | Full Potential | Priority |
| --- | --- | --- | --- | --- |
| RecognizeDocumentsRequest | Vision | ✅ Partial | 60% | HIGH |
| Table structure | Vision | ❌ No | Extract but discard | HIGH |
| Document classification | Vision | ❌ No | Route by type | MEDIUM |
| VNRecognizeTextRequest | Vision | ✅ Full | 100% | N/A |
| Handwriting detection | Vision | ❌ No | Flag handwritten | MEDIUM |
| Form fields | Vision | ❌ No | Extract fields | LOW |
| PDFKit | PDFKit | ✅ Full | 100% | N/A |
| NLLanguageRecognizer | NL | ✅ Full | 100% | N/A |
| SFSpeechRecognizer | Speech | ✅ Full | 100% | N/A |
| LanguageModelSession | Foundation Models | ❌ No | Wire up | HIGH |
| Logger | OSLog | ✅ Full | 100% | N/A |

---

## Honest Assessment

**Coverage: ~65% of exposed Apple APIs**

What we're using well:
- ✅ Text extraction (Vision, PDFKit)
- ✅ Language detection (NL)
- ✅ Audio transcription (Speech)
- ✅ Logging (OSLog)

Quick wins we're missing:
- 🔴 Table preservation (already extracted, just discard it)
- 🔴 Foundation Models wiring (exists but deactivated)
- 🟡 Document classification (simple, useful)

These aren't architectural gaps — they're just deferred priorities.
