# End-to-End Validation and Repair

Every conversion through Upmarket runs through a comprehensive validation and repair pipeline. This applies to **all conversion pathways**, regardless of how the markdown was generated.

## Conversion Pathways (All Validated)

| Pathway | Source | Validation Applied |
| --- | --- | --- |
| **Basic PDF** | PDFKit | ✅ Yes |
| **Scanned PDF** | Vision OCR | ✅ Yes |
| **Enhanced PDF** | Python + Docling | ✅ Yes |
| **AI PDF** | Python + Docling + VLM | ✅ Yes |
| **Audio** | Speech + Transcription | ✅ Yes |
| **Image** | Vision OCR | ✅ Yes |
| **+Writing Tools** | NL refinement | ✅ Yes |
| **+Foundation Models** | AI metadata extraction | ✅ Yes |

## The Pipeline

Every conversion, from any pathway, follows this sequence:

```
1. CONVERSION
   Source format → Markdown (via PDF, Vision, Docling, Speech, etc.)

2. WRITING TOOLS REFINEMENT
   Optional: Merge broken sentences, normalize text (macOS 15.1+)

3. FOUNDATION MODELS ENHANCEMENT
   Optional: Extract title, authors, topics, section summaries (macOS 26+)

4. DOCUMENT STRUCTURE VALIDATION & REPAIR ← THE KEY
   - Extract structure from original (headings, tables, lists)
   - Extract structure from converted
   - Compare and identify issues
   - Automatically repair (fix heading levels, spacing, etc.)
   - Log structure quality metrics

5. CONTENT VALIDATION
   - Check word retention (>70%)
   - Check output size is reasonable
   - Check extraction success
   - Check table/list counts match

6. RETURN FINAL MARKDOWN
   - Original structure intact
   - Content validated
   - Quality metrics logged
```

## What Gets Validated & Repaired

### Headings
- **Extracted:** All headings (# ## ### etc.)
- **Validated:** Count matches, levels correct, text preserved
- **Repaired:** Wrong levels fixed, spacing normalized
- **Works for:** All pathways

### Sections
- **Extracted:** Text between headings
- **Validated:** Order preserved, not empty
- **Repaired:** Reordered to match original, spacing fixed
- **Works for:** All pathways with document structure

### Tables
- **Extracted:** Count and structure (rows × columns)
- **Validated:** Count matches input
- **Repaired:** Alerts if missing (can't auto-repair)
- **Works for:** PDFs, Docling, images

### Lists
- **Extracted:** Count and nesting depth
- **Validated:** Count matches input
- **Repaired:** Alerts if missing
- **Works for:** PDFs, Docling, images

### Content
- **Extracted:** Word count, character count
- **Validated:** Retention >70%, no suspicious size/emptiness
- **Repaired:** N/A (content validation is non-blocking)
- **Works for:** All pathways

## Per-Pathway Behavior

### Basic PDF (PDFKit)
```
Input: PDF with clear headings/tables
Process: PDFKit extraction → structure validation
Output: Well-formed markdown with fixed heading levels
```

### Scanned PDF (Vision OCR)
```
Input: Scanned image pages
Process: Vision OCR → structure validation → repair
Output: OCR text with normalized markdown structure
```

### Enhanced PDF (Docling)
```
Input: PDF with complex layout
Process: Docling extraction → structure validation → repair
Output: Better layout understanding with validated structure
```

### AI-Enhanced PDF (Docling + VLM)
```
Input: PDF with complex layout
Process: Docling VLM → structure validation → repair → FM enhancement
Output: AI-understanding with correct structure and metadata
```

### Audio (Speech Recognition)
```
Input: Audio file
Process: Speech transcription → structure validation (N/A for audio)
Output: Transcript (audio rarely has formal structure)
```

### With Writing Tools (All Pathways)
```
Input: Any conversion output
Process: Conversion → writing tools → structure validation → repair
Output: Refined text with structure intact
```

### With Foundation Models (All Pathways)
```
Input: Any conversion output
Process: Conversion → FM extraction → structure validation → repair
Output: Content with AI-extracted metadata and validated structure
```

## Example: AI-Enhanced PDF Conversion Flow

**1. User converts PDF with AI enabled**
```
PDF (invoice with table, multiple sections)
  ↓ [Docling VLM]
Markdown with VLM understanding (good table detection)
  ↓ [Writing Tools]
Refined text (sentences merged if broken)
  ↓ [Foundation Models]
Added: title, authors, abstract, key topics
  ↓ [STRUCTURE VALIDATION]
Compare original structure to output
  Issues: Heading level wrong (1 vs 2), spacing missing
  Repair: Fix levels, add spacing
  ↓ [CONTENT VALIDATION]
Check: 85% word retention ✓, 3 tables found ✓, no corruption ✓
  ↓
Final Markdown (structure intact, content validated)
```

**2. Validation Report**

```
Structure Issues (Repaired):
- ERROR: Heading level wrong for "Invoice Details" (was 1, fixed to 2)
- WARNING: Missing spacing between sections (fixed)

Content Metrics:
- Word retention: 85%
- Tables found: 3 (expected: 3) ✓
- Lists found: 0
- Structure retention: 92%

Logs:
[ERROR] Heading level wrong for "Invoice Details" (was 1, fixed to 2)
[WARNING] Missing spacing between sections (fixed)
Structure retention: 92% (headings: 5/5, tables: 3/3)
```

## Quality Guarantees by Pathway

| Metric | Basic | Scanned | Enhanced | AI | With FM |
| --- | --- | --- | --- | --- | --- |
| Heading structure preserved | ✅ | ✅ | ✅ | ✅ | ✅ |
| Section order preserved | ✅ | ✅ | ✅ | ✅ | ✅ |
| Table count validated | ✅ | ⚠️ | ✅ | ✅ | ✅ |
| List count validated | ✅ | ⚠️ | ✅ | ✅ | ✅ |
| Word retention > 70% | ✅ | ⚠️ | ✅ | ✅ | ✅ |
| Structure auto-repair | ✅ | ✅ | ✅ | ✅ | ✅ |

**Legend:**
- ✅ Fully supported
- ⚠️ Best-effort (OCR may not perfectly detect tables/lists)

## Implementation

**File:** `Upmarket/Upmarket/Services/ConversionPostProcessor.swift`

```swift
enum ConversionPostProcessor {
    static func process(_ output: ConversionOutput) async -> ConversionOutput {
        // 1. Extract original structure for validation
        let originalMarkdown = output.markdown
        
        // 2. Apply refinements (Writing Tools, Foundation Models, etc.)
        var finalMarkdown = applyWritingTools(...)
        finalMarkdown = applyFoundationModels(finalMarkdown)
        
        // 3. VALIDATE & REPAIR STRUCTURE
        let structureReport = DocumentStructureValidator.validateAndRepair(
            originalMarkdown: originalMarkdown,
            convertedMarkdown: finalMarkdown
        )
        
        // Use repaired markdown if issues detected
        if let repaired = structureReport.reformattedMarkdown {
            finalMarkdown = repaired
        }
        
        // 4. VALIDATE CONTENT
        let contentReport = ConversionValidator.validate(...)
        
        // 5. Return final markdown
        return ConversionOutput(markdown: finalMarkdown, ...)
    }
}
```

**Called from:** `ConversionRunner.run()` (after all conversions complete, before returning result)

**Result:** All markdown is validated and repaired before delivery to user.
