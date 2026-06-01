# Serial vs Parallel Benchmarks

This file records release evidence for conversion queue concurrency decisions. Do not change queue concurrency from these numbers alone; rerun the benchmark on the release candidate and compare quality, failures, wall time, and system load.

## 2026-06-01 - `python-fast-pdfium`

Host: Mac mini M4 Pro-class local benchmark host. Corpus: `tests/corpus`, PDF category, 60 documents. Command:

```sh
scripts/benchmark_concurrency.py --pathway python-fast-pdfium --workers 4 --json-output reports/concurrency-python-fast-pdfium.json --markdown-output reports/concurrency-python-fast-pdfium.md
```

| Mode | Workers | Docs | Failures | Avg Score | Converter Avg | Wall Time | Throughput | Load Before | Load After |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| serial | 1 | 60 | 1 | 81.5% | 0.0314s | 3.970s | 15.1143 docs/s | 4.99, 3.40, 4.15 | 4.91, 3.41, 4.15 |
| parallel | 4 | 60 | 1 | 81.5% | 0.0314s | 1.067s | 56.2433 docs/s | 4.91, 3.41, 4.15 | 4.91, 3.41, 4.15 |

Result: 4-worker isolated parallel conversion improved throughput for the fast PDF pathway without a score or failure regression in this run. This does not yet justify changing app queue behavior for all pathways; repeat for native OCR, enhanced/model paths, cancellation, and memory pressure before promotion.
