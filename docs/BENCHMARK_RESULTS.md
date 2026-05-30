# Upmarket Benchmark Results

**Corpus:** Docling project test data (MIT licensed, 14 documents with ground truth)  
**Ground truth:** Docling v2 Enhanced pipeline output (`.md` files)  
**Date:** 2026-05-31

## Pipeline Comparison

| Document | Fast | Enhanced | Delta |
|---|---|---|---|
| 2203.01017v2 (arXiv) | 39% | TIMEOUT | — |
| 2206.01062 (arXiv) | 36% | **95%** | +59% |
| 2305.03393v1 (arXiv) | 41% | **95%** | +54% |
| 2305.03393v1-pg9 | 52% | **95%** | +43% |
| amt_handbook_sample | 64% | **95%** | +31% |
| code_and_formula | 93% | **95%** | +2% |
| multi_page | 64% | **95%** | +31% |
| normal_4pages | 37% | **95%** | +58% |
| picture_classification | 94% | **95%** | +1% |
| redp5110_sampled (IBM) | 23% | **94%** | +71% |
| right_to_left_01 (RTL) | 56% | **95%** | +39% |
| right_to_left_02 (RTL) | 90% | **95%** | +5% |
| right_to_left_03 (RTL) | 61% | **95%** | +34% |
| word_sample (DOCX) | 67% | **94%** | +27% |
| **Overall** | **58%** | **94%** | **+36%** |

## Key Findings

### Fast Path (pdfium + postprocessor, zero download)
- **93-94%** on clean single-column PDFs — excellent
- **36-41%** on multi-column academic papers — expected, needs Enhanced
- **67%** on DOCX — markitdown output vs Docling ML
- **23%** on IBM Redbook complex layout — needs Enhanced
- Speed: 0.0-0.4s per document

### Enhanced Pipeline (Docling ML, 342MB download)
- **94-95%** across virtually all document types
- Matches ground truth because ground truth IS Docling Enhanced output
- 1 timeout (2203.01017v2 — large arXiv paper, >30s with 30s benchmark limit)
- Speed: 4-16s per document (ML inference)

### What This Means for Users

| User drops | Recommended path | Expected quality |
|---|---|---|
| Clean digital PDF | Fast (instant) | 90-94% |
| Multi-column / scanned | Enhanced (342MB download) | 94-95% |
| Word / DOCX | Fast via markitdown | 67-94% |
| RTL document | Enhanced | 95% |
| Complex IBM/technical | Enhanced | 94% |

## Scoring Methodology

Scores are measured against Docling Enhanced ground truth using:
- **Heading recall** (30%) — fraction of GT headings found in output
- **Table accuracy** (25%) — table count match
- **Content completeness** (30%) — word count ratio + char n-gram similarity
- **Markdown validity** (10%) — no broken syntax
- **Artifact-free** (5%) — no page numbers, ligatures, soft hyphens

## Next Steps

1. Increase benchmark timeout to 120s for large papers
2. Add Enhanced+AI pipeline comparison once SmolDocling models downloaded
3. Expand corpus: DocLayNet (CDLA-Permissive), scanned docs, PPTX/XLSX
4. Add Vision RecognizeDocumentsRequest pipeline once macOS 26 ships
