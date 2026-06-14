# HuggingFace Dataset Validation

This directory contains setup and validation scripts for evaluating Upmarket against large document datasets from HuggingFace.

## Datasets

Three datasets are used for comprehensive validation:

- **pdfa-eng-wds**: Real-world PDFs with embedded text → exact ground truth for fast/enhanced pipeline fidelity
- **idl-wds**: Scanned industrial documents (no text GT) → OCR quality stress test for Vision/Docling scanned pathways
- **docvqa-wds**: Document images + annotated Q&A → end-to-end information-preservation test

## Setup

### 1. Install git-xet and clone datasets

```bash
bash scripts/datasets/download_hf_datasets.sh
```

This installs `git-xet` via Homebrew, initializes it, and clones all four repos. The operation is idempotent; it skips already-cloned repos.

### 2. Prepare manifests (one-time)

```bash
python3 scripts/datasets/prepare_hf_corpus.py --dataset all --sample 200 --seed 42
```

This extracts a stratified sample of 200 documents from each dataset and generates:
- `tests/datasets/manifests/hf_pdfa_manifest.json`
- `tests/datasets/manifests/hf_idl_manifest.json`
- `tests/datasets/manifests/hf_docvqa_manifest.json`

These manifests are committed to git. Document files live in `tests/datasets/huggingface/` (gitignored).

## Evaluation

Run all benchmarks:

```bash
bash scripts/datasets/benchmark_hf.sh --dataset all --fail-below 75
```

This runs three evaluators:
1. `evaluate_pdfa.py` — Text fidelity (CER, WER, completeness vs embedded text GT)
2. `evaluate_idl.py` — OCR quality (confidence, artifact count, coverage heuristic)
3. `evaluate_docvqa.py` — Q&A accuracy (hit rate, exact match, F1 score)

Results are written to:
- `reports/hf-pdfa-YYYYMMDD-HHMMSS.json`
- `reports/hf-idl-YYYYMMDD-HHMMSS.json`
- `reports/hf-docvqa-YYYYMMDD-HHMMSS.json`

## CI Integration

These benchmarks run as part of the `release` gate mode:

```bash
scripts/ci/gate.sh release
```

They skip gracefully if datasets are not downloaded (the manifests are always present). The baselines are defined in:
```
docs/release/hf_dataset_baseline.json
```

To seed initial thresholds after the first run:

```bash
python3 scripts/ci/bootstrap_hf_baseline.py
git add docs/release/hf_dataset_baseline.json
git commit -m "Bootstrap HuggingFace dataset baseline thresholds"
```

## Directory Structure

```
tests/datasets/
├── manifests/
│   ├── hf_pdfa_manifest.json       # Committed: 200-doc sample
│   ├── hf_idl_manifest.json        # Committed: 200-doc sample
│   └── hf_docvqa_manifest.json     # Committed: 200-doc sample
├── huggingface/                     # Gitignored: local repos (git-xet)
│   ├── pdfa-eng-wds/
│   ├── idl-wds/
│   ├── docvqa-wds/
│   └── docvqa-single-page-questions/
└── (extracted files)                # Gitignored: expanded documents
```

## Notes

- Manifests use the same schema as `tests/corpus/manifest.json` and are validated by `scripts/ci/validate_hf_corpus.py`
- Ground truth for PDFA is extracted using `pdfplumber` (embedded text in PDFs)
- IDL and DocVQA have no text ground truth; evaluation uses OCR confidence and Q&A matching heuristics
- The baseline thresholds (`docs/release/hf_dataset_baseline.json`) should be updated as the pipeline improves
