#!/usr/bin/env python3
"""Runtime-free verification of the benchmark scorer's manifest handling.

Exercises the parts of benchmark_scorer.run_benchmark that do NOT need the
embedded Python runtime/models: document selection, path resolution, and format
grouping. Confirms the scorer reads the current Document+GroundTruth manifest
schema and that its report categories will line up with the corpus baseline.

Run from the repo root: python3 scripts/dev/verify_benchmark_loader.py
"""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path("scripts").resolve()))
from benchmark_scorer import manifest_format, resolve_corpus_path  # noqa: E402

CORPUS_DIR = Path("tests/corpus")
BASELINE = Path("docs/release/corpus_baseline.json")


def main() -> int:
    errors: list[str] = []
    manifest = json.loads((CORPUS_DIR / "manifest.json").read_text())
    docs = manifest.get("documents", [])
    if not docs:
        print("error: manifest has no documents")
        return 1

    # 1) Every document and ground-truth path resolves to a real file.
    missing_docs = 0
    missing_gt = 0
    for doc in docs:
        doc_rel = doc.get("document") or doc.get("file", "")
        if not resolve_corpus_path(CORPUS_DIR, doc_rel).exists():
            missing_docs += 1
        gt = doc.get("ground_truth")
        if not gt or not resolve_corpus_path(CORPUS_DIR, gt).exists():
            missing_gt += 1
    if missing_docs:
        errors.append(f"{missing_docs}/{len(docs)} document paths did not resolve to a file")
    if missing_gt:
        errors.append(f"{missing_gt}/{len(docs)} ground-truth paths did not resolve to a file")

    # 2) Grouping by format yields real format keys (not all "unknown").
    grouped = Counter(manifest_format(d) for d in docs)
    if grouped.get("unknown"):
        errors.append(f"{grouped['unknown']} documents grouped as 'unknown' (format not read)")

    # 3) The report's format keys cover every category the corpus baseline gates,
    #    so validate_corpus_baseline --results won't fail on a missing category.
    baseline = json.loads(BASELINE.read_text())
    for pipeline, cfg in baseline.get("pipelines", {}).items():
        gated = set(cfg.get("minimum_category_percent", {}))
        absent = sorted(gated - set(grouped))
        if absent:
            errors.append(f"baseline pipeline '{pipeline}' gates categories absent from corpus: {absent}")

    print(f"documents: {len(docs)}")
    print(f"resolved:  documents={len(docs) - missing_docs}, ground_truth={len(docs) - missing_gt}")
    print(f"by format: {dict(sorted(grouped.items()))}")

    if errors:
        for e in errors:
            print(f"error: {e}", file=sys.stderr)
        return 1
    print("ok: benchmark scorer reads the current manifest schema and aligns with the baseline")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
