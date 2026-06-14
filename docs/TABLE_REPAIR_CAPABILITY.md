# Table Repair Capability

## What Apple Exposes

Apple's `RecognizeDocumentsRequest` (Vision framework, macOS 26+) exposes **full table structure**:

```swift
DocumentObservation.Container.Table {
    var rows: [DocumentObservation.Container.Row]  // Array of rows
}

DocumentObservation.Container.Row {
    // Each row is actually an array of cell containers
    var cells: [DocumentObservation.Container]  // Array of cells
    subscript(index: Int) -> DocumentObservation.Container  // Access cell by index
}

DocumentObservation.Container {  // Each cell
    var text: DocumentObservation.Container.Text  // Cell content
    var bbox: CGRect  // Cell bounding box
}
```

So we get:
- ✅ Table structure (rows × columns)
- ✅ Each cell's content (extracted text)
- ✅ Cell boundaries (bounding boxes)
- ✅ Order and nesting information

**We have everything needed to reconstruct tables.**

## Current Limitation

We extract tables but don't preserve the **structured data**:

```swift
// Current (loses structure after conversion)
for table in doc.tables {
    let markdown = tableToMarkdown(table)  // Convert to markdown string
    parts.append(markdown)
    // table object is discarded — only string remains
}

// Result: Markdown string, original structure lost
```

**Problem:** Once converted to markdown, we lose:
- Exact cell boundaries
- Cell formatting
- Original cell order
- Structured relationships

## The Solution: Preserve Structured Data

**Step 1:** Don't discard Vision table objects

```swift
struct ConversionOutput {
    let markdown: String
    let originalTables: [TableRepair.StructuredTable]  // NEW: Keep structured data
    let originalLists: [ListRepair.StructuredList]     // NEW: Future
}
```

**Step 2:** Extract structure from Vision

```swift
@available(macOS 26, *)
private static func extractStructuredTables(doc: DocumentObservation) -> [TableRepair.StructuredTable] {
    var tables: [TableRepair.StructuredTable] = []
    
    for visionTable in doc.tables {
        var rows: [[String]] = []
        
        for row in visionTable.rows {
            var cellStrings: [String] = []
            for cell in row {
                let content = textFromContainer(cell.text)
                cellStrings.append(content)
            }
            rows.append(cellStrings)
        }
        
        tables.append(TableRepair.StructuredTable(rows: rows))
    }
    
    return tables
}
```

**Step 3:** Use structured data in repair

```swift
let missingTables = TableRepair.detectMissingTables(
    originalTables: output.originalTables,  // From Vision extraction
    outputMarkdown: convertedMarkdown       // From conversion
)

if !missingTables.isEmpty {
    let repaired = TableRepair.repairMissingTables(
        markdown: convertedMarkdown,
        insertTables: missingTables
    )
    return repaired
}
```

## Example: Full Table Repair

**Original PDF:**
```
Name | Age | City
John | 28  | NYC
Jane | 31  | LA

(Plus other content)
```

**Vision Extraction (Structured):**
```swift
StructuredTable(
    rows: [
        ["Name", "Age", "City"],
        ["John", "28", "NYC"],
        ["Jane", "31", "LA"]
    ]
)
```

**Conversion Failure** (table missing):
```markdown
Name Age City

John is 28 years old and lives in NYC.
Jane is 31 and lives in LA.
```

**Table Repair Process:**
1. Detect: Expected 1 table, found 0
2. Extract: Get table from `originalTables`
3. Repair: Insert structured table back into markdown
4. Result:
   ```
   | Name | Age | City |
   | --- | --- | --- |
   | John | 28 | NYC |
   | Jane | 31 | LA |

   John is 28 years old and lives in NYC.
   Jane is 31 and lives in LA.
   ```

## Why This Works

✅ **Apple provides structure** — RecognizeDocumentsRequest gives complete table data
✅ **We can preserve it** — Store as structured data, not markdown string
✅ **We can reconstruct it** — Convert back to markdown when repairing
✅ **We can validate it** — Compare structure between original and output

## Current State

- ✅ TableRepair module created (ready to use)
- ⚠️ VisionDocumentExtractor needs modification (preserve structured data)
- ⚠️ ConversionOutput needs modification (add originalTables field)
- ⚠️ DocumentStructureValidator needs modification (use structured data)
- ⚠️ ConversionPostProcessor needs modification (call table repair)

## Why We Can't Currently Repair Tables

1. **Architectural loss:** Vision table objects are converted to markdown strings immediately
2. **No preservation:** Structured data thrown away after markdown conversion
3. **Markdown only:** By validation time, we only have markdown text, not table objects
4. **Position unknown:** Don't know where in document table should be inserted

## Why We CAN Repair Tables (Potential)

1. ✅ **Apple provides complete structure** — DocumentObservation.Container.Table
2. ✅ **Cell content included** — All text extracted
3. ✅ **Column info available** — Row width, cell boundaries
4. ✅ **Order preserved** — Rows in sequence

## Implementation Path

To enable full table repair:

```
1. Modify VisionDocumentExtractor
   - Keep Vision table objects
   - Extract to StructuredTable format
   - Return alongside markdown

2. Modify ConversionOutput
   - Add originalTables: [StructuredTable]
   - Add originalLists: [StructuredList]

3. Modify DocumentStructureValidator
   - Accept structured table data
   - Compare at structure level
   - Pass to TableRepair

4. Modify TableRepair
   - Detect position (after which heading)
   - Insert complete table back
   - Maintain formatting

5. Modify ConversionPostProcessor
   - Extract structured data from output
   - Call TableRepair.repairMissingTables()
   - Use repaired markdown
```

## Benefits Once Implemented

| Feature | Before | After |
| --- | --- | --- |
| Detect missing tables | ✅ Yes | ✅ Yes |
| Repair missing tables | ❌ No | ✅ Yes |
| Reconstruct table content | ❌ No | ✅ Yes |
| Preserve cell order | ❌ No | ✅ Yes |
| Preserve cell boundaries | ❌ No | ✅ Yes |
| Handle multi-row headers | ❌ No | ✅ Possible |

## Why It's Important

**Example Scenario:**

User converts a 10-page financial report:
- Page 3: Revenue table
- Page 7: Expense breakdown table  
- Page 9: Year-over-year comparison table

If Docling extraction fails on pages 3 and 9:
- **Before:** Tables marked as missing, can't recover
- **After:** Tables automatically reconstructed from Vision data

User gets complete document, not gaps.

## Next Steps

This is a ready-to-implement feature. The infrastructure is in place; just needs:
1. Thread structured data through pipeline
2. Call TableRepair in DocumentStructureValidator
3. Test on PDFs with complex tables

**Priority:** Medium (useful but not critical for MVP)
