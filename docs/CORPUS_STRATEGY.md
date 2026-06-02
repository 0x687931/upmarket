# Upmarket Validation Corpus Strategy

## The Problem

Document-to-Markdown conversion quality is hard to measure because:
- "Good" Markdown is subjective
- Different document types have different success criteria
- A change that improves academic PDFs may regress invoices
- We have multiple extraction pipelines that need independent benchmarking

Without a structured corpus and automated scoring, every change is a guess.

---

## Corpus Design Principles

### 1. Ground Truth First
Every test document must have a **manually verified expected output** — the "gold standard" Markdown. Quality is measured as deviation from ground truth, not subjective judgement.

### 2. Dimension Coverage
The corpus must stress every dimension we care about independently. A single document tests too many things at once.

### 3. Verifiable, Not Just Readable
Scoring must be automated and deterministic — not "does this look good?" but "does this contain the expected headings, tables, paragraphs?"

### 4. Source Diversity
Documents must come from real-world sources, not synthetic test data. Synthetic docs miss the weird edge cases that real users encounter.

---

## Corpus Structure

```
tests/corpus/
├── README.md              ← this file summary
├── manifest.json          ← machine-readable corpus index
│
├── pdf_digital/           ← clean programmatic PDFs
│   ├── academic/          ← research papers, theses
│   ├── business/          ← reports, contracts, invoices
│   ├── technical/         ← manuals, specs, datasheets
│   └── multicolumn/       ← newspaper-style, complex layout
│
├── pdf_scanned/           ← image-based PDFs (OCR path)
│   ├── clean/             ← good scan quality
│   ├── degraded/          ← low res, skewed, noisy
│   └── handwritten/       ← notes, forms
│
├── office/
│   ├── docx/              ← Word documents
│   ├── pptx/              ← PowerPoint presentations
│   └── xlsx/              ← Excel spreadsheets
│
├── web/
│   ├── html/              ← web pages
│   └── epub/              ← ebooks
│
├── data/
│   ├── csv/
│   ├── json/
│   └── xml/
│
├── audio/                 ← for SFSpeechRecognizer
│   ├── clean/             ← clear speech
│   └── noisy/             ← background noise, accents
│
└── edge_cases/
    ├── encrypted/         ← password-protected PDFs
    ├── multilingual/      ← mixed-language docs
    ├── tables_complex/    ← merged cells, nested tables
    ├── math/              ← equations, formulas
    └── rtl/               ← Arabic, Hebrew right-to-left
```

---

## Document Selection Criteria

### Per category: 10-20 documents minimum
### Each document needs:
1. **Source file** — original PDF/DOCX/etc.
2. **Gold standard** — `filename.expected.md` — manually verified correct output
3. **Metadata** — `filename.meta.json` — what the document contains

```json
// example: academic_paper_001.meta.json
{
  "id": "academic_paper_001",
  "format": "pdf_digital",
  "category": "academic",
  "language": "en",
  "pages": 12,
  "expected_features": {
    "headings": ["Abstract", "Introduction", "Methods", "Results", "Conclusion"],
    "tables": 3,
    "has_equations": true,
    "has_figures": true,
    "estimated_words": 8500
  },
  "known_challenges": ["multi-column layout", "figure captions", "footnotes"],
  "source": "arxiv.org",
  "license": "CC BY 4.0"
}
```

---

## Scoring Dimensions

### 1. Structural Accuracy (automated)
Does the output contain the right structural elements?

```python
def score_structure(output_md, expected_meta):
    scores = {}
    
    # Heading detection rate
    expected_h = expected_meta["expected_features"]["headings"]
    found_h = extract_headings(output_md)
    scores["heading_recall"] = len(set(found_h) & set(expected_h)) / len(expected_h)
    
    # Table detection
    expected_tables = expected_meta["expected_features"]["tables"]
    found_tables = count_md_tables(output_md)
    scores["table_accuracy"] = 1.0 if found_tables == expected_tables else found_tables / max(expected_tables, 1)
    
    # Word count proximity (±20% = pass)
    expected_words = expected_meta["expected_features"]["estimated_words"]
    actual_words = count_words(output_md)
    ratio = actual_words / expected_words
    scores["content_completeness"] = 1.0 if 0.8 <= ratio <= 1.2 else ratio
    
    return scores
```

### 2. Text Quality (NLP-assisted)
- BLEU score against gold standard (character n-gram overlap)
- Edit distance for key sections (abstract, headings)
- Language consistency (NLLanguageRecognizer on output)

### 3. Markdown Validity (syntax)
- Parses without error
- No broken table syntax
- No orphaned heading markers
- No raw PDF artifacts (page numbers mid-text, ligature chars)

### 4. Pipeline-Specific Scores
Each pipeline (pdfium/fast, Enhanced, AI, Vision) scored independently so regressions are isolated.

---

## Automated Benchmark Runner

```bash
# Run full benchmark
./scripts/benchmark.sh

# Run for specific pipeline only
./scripts/benchmark.sh --pipeline fast

# Run for specific category
./scripts/benchmark.sh --category pdf_scanned

# Compare two pipeline versions
./scripts/benchmark.sh --compare fast enhanced
```

Output:
```
Upmarket Benchmark Results
==========================
Pipeline: fast (pdfium + postprocessor + NL)

Category          | Documents | Heading% | Tables% | Completeness | Overall
------------------|-----------|----------|---------|--------------|--------
pdf_digital/academic  |    15    |   94%    |   87%   |     96%      |  92%
pdf_digital/business  |    12    |   91%    |   95%   |     98%      |  95%
pdf_scanned/clean     |     8    |   72%    |   45%   |     88%      |  68%
pdf_scanned/degraded  |     5    |   51%    |   21%   |     71%      |  48%
office/docx           |    10    |   97%    |   98%   |     99%      |  98%
edge_cases/tables_complex |  6  |   85%    |   73%   |     91%      |  83%

TOTAL             |    56    |   88%    |   82%   |     94%      |  88%

Regressions vs last run: 0
```

---

## Where to Get Documents

### Free/Open Sources
- **arXiv.org** — academic PDFs, CC BY 4.0, diverse topics
- **Project Gutenberg** — EPUBs and PDFs, public domain
- **Government documents** — SEC filings, court docs, public domain
- **Wikipedia** — HTML, CC BY-SA
- **OpenDocument samples** — OASIS test suite for DOCX/PPTX/XLSX
- **UN documents** — multilingual PDFs (6 official UN languages)
- **NIST test corpus** — scanned document test sets

### Synthetic Edge Cases (generate programmatically)
- Tables with merged cells
- Mixed-language documents
- Documents with specific Unicode challenges
- Password-protected PDFs (generate with pypdfium2)

### Real-World (anonymised)
- Contribute your own documents (with PII removed)
- Community contributions with clear licensing

---

## Ground Truth Creation Process

For each document:
1. Convert with **best available pipeline** (Enhanced or AI)
2. **Manually review and correct** output in a Markdown editor
3. Save as `filename.expected.md`
4. Record metadata in `filename.meta.json`
5. Commit to corpus repo

This is time-consuming but only needs doing once per document.
**Target: 100 documents across all categories for v1 validation.**

---

## CI Integration

Validate the manifest and release baseline on every PR:
```yaml
- name: Validate corpus baseline
  run: scripts/ci/validate_corpus_baseline.py
```

Run the benchmark before every release and fail if the score falls below the stored baseline:
```yaml
- name: Run corpus benchmark
  run: |
    ./scripts/benchmark.sh --pipeline fast --json-output reports/corpus-fast.json --fail-below 76
    scripts/ci/validate_corpus_baseline.py --results reports/corpus-fast.json
```

Baseline values live in `docs/release/corpus_baseline.json`. A lower score is a release blocker unless the baseline is intentionally updated with review notes explaining the quality tradeoff.

---

## Corpus Repository

Keep the corpus **separate from the app repo**:
- `github.com/0x687931/upmarket-corpus` (private)
- Keeps app repo lightweight
- Corpus can be updated independently
- Reference via git submodule or download script

---

## Priority: What to Build First

### Phase 1 — Minimum Viable Corpus (before first release)
- 15 clean digital PDFs (academic + business)
- 5 DOCX files
- 5 scanned PDFs
- 3 HTML files
- Total: ~28 documents
- Run benchmark before every release, catch regressions

### Phase 2 — Broad Coverage (after launch)
- All categories, 100+ documents
- Automated CI benchmark
- Community contributions

### Phase 3 — Continuous Improvement
- Use production conversions (opt-in, anonymised) as new test cases
- Track quality trends over releases
- A/B test pipeline changes before shipping
