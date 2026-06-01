# Serial vs Parallel Benchmarks

This file records release evidence for conversion queue concurrency decisions. Do not change queue concurrency from these numbers alone; rerun the benchmark on the release candidate and compare quality, failures, wall time, and system load.

## 2026-06-01 - `python-fast-pdfium`

Host: Mac mini M4 Pro-class local benchmark host. Corpus: `tests/corpus`, PDF category, 60 documents. Command:

```sh
scripts/benchmark_concurrency.py --pathway python-fast-pdfium --workers 4 --json-output reports/concurrency-python-fast-pdfium.json --markdown-output reports/concurrency-python-fast-pdfium.md
```

| Mode | Workers | Docs | Blocked | Failures | Avg Score | Converter Avg | Wall Time | Throughput | Load Before | Load After |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| serial | 1 | 60 | 1 | 0 | 81.5% | 0.0295s | 3.876s | 15.4815 docs/s | 1.75, 2.20, 3.13 | 1.77, 2.20, 3.13 |
| parallel | 4 | 60 | 1 | 0 | 81.5% | 0.0315s | 1.074s | 55.8634 docs/s | 1.77, 2.20, 3.13 | 1.77, 2.20, 3.13 |

Result: 4-worker isolated parallel conversion improved throughput for the fast PDF pathway without a score or failure regression in this run. The single blocked document is the password-protected corpus PDF without a supplied password, which is expected blocked behavior rather than converter failure. This does not yet justify changing app queue behavior for all pathways; repeat for native OCR, enhanced/model paths, cancellation, and memory pressure before promotion.
