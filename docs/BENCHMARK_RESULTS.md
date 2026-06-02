# Upmarket Benchmark Results

**Corpus:** Docling project test data (MIT licensed)  
**Documents:** 185 files across 12 format categories  
**Ground truth:** Docling v2 Enhanced pipeline output (14 files have `.md` GT)  
**Date:** 2026-05-31

---

## Full Comparison: Fast vs Enhanced (All 185 Documents)

| Category | Docs | Fast | Enhanced | Delta | Winner |
|---|---|---|---|---|---|
| asciidoc | 3 | 90% | 92% | +2% | tie |
| audio | 9 | 69% | n/a | — | fast (only option) |
| csv | 9 | 86% | 90% | +4% | enhanced |
| docx | 25 | 89% | 93% | +4% | enhanced |
| html | 30 | 88% | 87% | -1% | tie |
| image | 15 | 69% | 73% | +4% | enhanced |
| pdf | 60 | 81% | 84% | +3% | enhanced |
| pptx | 6 | 94% | 84% | **-10%** | **fast** |
| video | 4 | 69% | n/a | — | fast (only option) |
| webvtt | 4 | 95% | 95% | 0% | tie |
| xlsx | 7 | 86% | 90% | +4% | enhanced |
| xml | 12 | 72% | 90% | **+18%** | enhanced |
| **OVERALL** | **185** | **82%** | **86%** | **+4%** | enhanced |

---

## PDF Deep-Dive (Ground Truth Available)

| Document | Fast | Enhanced | Delta | Notes |
|---|---|---|---|---|
| code_and_formula | 93% | 95% | +2% | Clean single-column |
| picture_classification | 94% | 95% | +1% | Clean text |
| right_to_left_02 | 90% | 95% | +5% | RTL Hebrew |
| amt_handbook_sample | 64% | 95% | +31% | Multi-section |
| multi_page | 64% | 95% | +31% | Pagination |
| right_to_left_03 | 61% | 95% | +34% | RTL Hebrew |
| right_to_left_01 | 56% | 95% | +39% | RTL Hebrew |
| 2305.03393v1-pg9 | 52% | 95% | +43% | Multi-column academic |
| 2305.03393v1 | 41% | 95% | +54% | Multi-column + math |
| 2203.01017v2 | 39% | TIMEOUT | — | Large arXiv |
| normal_4pages | 37% | 95% | +58% | Complex layout |
| 2206.01062 | 36% | 95% | +59% | Dense academic |
| redp5110_sampled | 23% | 94% | +71% | IBM Redbook complex |
| word_sample (DOCX) | 67% | 94% | +27% | Markitdown vs Docling ML |

---

## Key Findings

### Fast Path (pdfium + markitdown, zero download, instant)
- **94-95%** on clean PDFs, PPTX, WebVTT — excellent, no download needed
- **86-90%** on DOCX, HTML, CSV, XLSX — good for everyday documents  
- **81%** on PDFs overall — degraded on multi-column academic (36-52%)
- **69%** on audio/video/images — metadata-only, content not transcribed
- **72%** on XML — XBRL/USPTO documents partially parsed
- **OVERALL: 82%** across 185 documents

### Enhanced Pipeline (Docling ML, 342MB download, 4-30s)
- **95%** on PDF documents with ground truth — matches source output
- **+18%** uplift on XML (XBRL/USPTO structured documents)
- **+4%** uplift on DOCX, CSV, XLSX
- **-10%** on PPTX — fast path (markitdown) actually outperforms Docling here
- **OVERALL: 86%** — +4% over fast path

### Unexpected Findings
1. **PPTX: Fast wins** — markitdown scores 94% vs Enhanced 84%. Docling's PPTX parser is not as good as python-pptx.
2. **HTML: tie** — both 87-88%. markitdown and Docling both handle HTML well.
3. **Audio/Video/WebVTT: Fast only** — Enhanced doesn't add value for time-based media.
4. **XML: Enhanced wins big (+18%)** — XBRL and USPTO patent XML have complex structure that Docling handles much better.

### Pipeline Routing Recommendation

| Format | Use | Reason |
|---|---|---|
| PDF (clean, digital) | Fast | 93-95%, instant |
| PDF (scanned, multi-column, complex) | Enhanced | +31-71% uplift |
| DOCX | Fast or Enhanced | +4% for Enhanced |
| PPTX | **Fast** | Fast actually scores higher |
| XLSX, CSV | Enhanced if available | +4% uplift |
| HTML | Either | Tied |
| XML/XBRL | Enhanced | +18% uplift |
| Audio, Video, WebVTT | Fast only | Enhanced doesn't help |
| Images | Fast | Metadata extraction |

---

## Errors & Edge Cases

| File | Pipeline | Error | Action needed |
|---|---|---|---|
| docx_external_image.docx | Fast | mammoth fails on external image ref | Add fallback |
| powerpoint_unrecognized_shape.pptx | Fast | python-pptx shape type | Handle gracefully |
| sample_10s_audio-flac.flac / .x-flac | Fast | FLAC not in markitdown | Add FLAC support |
| sample_10s_video-avi / .mov | Fast | AVI/MOV not in markitdown | Add or document as unsupported |
| webp-test.webp | Fast | WebP missing dependency | Add webp support |
| 2203.01017v2.pdf | Enhanced | >30s timeout | Raise timeout to 120s |

---

## Scoring Methodology

Scores against ground truth (14 files) use:
- Heading recall (30%), table count accuracy (25%), content completeness (30%), markdown validity (10%), artifact-free (5%)

Scores without ground truth use heuristics:
- Non-empty output → 69% baseline, +bonus for structure detected

---

## Performance

| Pipeline | Median time | Max time | Download |
|---|---|---|---|
| Fast | 0.0s | 0.5s | 0 MB |
| Enhanced | 5s | 30s+ | 342 MB |
| Upmarket AI | TBD | TBD | +500 MB |
