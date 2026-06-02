#!/usr/bin/env python3
"""Benchmark Apple PDFKit extraction against the PDF corpus."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SWIFT_SCRIPT = ROOT / "scripts" / "benchmark_pdfkit.swift"
SCORER = ROOT / "scripts" / "benchmark_scorer.py"

sys.path.insert(0, str(ROOT / "scripts"))
from benchmark_scorer import benchmark_host, score_document  # noqa: E402


def load_manifest() -> dict:
    return json.loads((ROOT / "tests" / "corpus" / "manifest.json").read_text(encoding="utf-8"))


def ground_truth(meta: dict) -> str | None:
    key = meta.get("ground_truth")
    if not key:
        return None
    candidates = [
        ROOT / "tests" / "corpus" / key,
        ROOT / "tests" / "corpus" / "docling" / "docling" / key,
    ]
    for path in candidates:
        if path.exists():
            return path.read_text(encoding="utf-8", errors="replace")
    return None


def main() -> int:
    output = Path("reports/corpus-swift-pdfkit.json")
    if "--json-output" in sys.argv:
        index = sys.argv.index("--json-output")
        output = Path(sys.argv[index + 1])

    proc = subprocess.run(
        ["swift", "-module-cache-path", "build/swift-module-cache", str(SWIFT_SCRIPT)],
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=180,
    )
    if proc.returncode != 0:
        print(proc.stderr, file=sys.stderr)
        return proc.returncode

    manifest = load_manifest()
    by_id = {doc["id"]: doc for doc in manifest["documents"]}
    documents = []
    for line in proc.stdout.splitlines():
        if not line.startswith("{"):
            continue
        result = json.loads(line)
        meta = by_id[result["id"]]
        if result.get("error"):
            score = None
            overall = 0.0
        else:
            score = score_document(result["markdown"], meta, ground_truth(meta))
            overall = round(score.overall * 100, 1)
        documents.append({
            "id": result["id"],
            "file": result["file"],
            "category": "pdf",
            "overall_percent": overall,
            "heading_recall_percent": round(score.heading_recall * 100, 1) if score else 0.0,
            "table_accuracy_percent": round(score.table_accuracy * 100, 1) if score else 0.0,
            "content_completeness_percent": round(score.content_completeness * 100, 1) if score else 0.0,
            "markdown_valid": score.markdown_valid if score else False,
            "artifacts_found": score.artifacts_found if score else 0,
            "elapsed_seconds": round(float(result["elapsed_seconds"]), 3),
            "elapsed_runs_seconds": [round(float(result["elapsed_seconds"]), 3)],
            "error": result.get("error"),
        })

    avg = sum(doc["overall_percent"] for doc in documents) / len(documents) if documents else 0.0
    elapsed = sum(doc["elapsed_seconds"] for doc in documents) / len(documents) if documents else 0.0
    report = {
        "version": 1,
        "pipeline": "swift-pdfkit",
        "pathway": "swift-pdfkit",
        "repeat_count": 1,
        "compute_mode": "cpu",
        "benchmark_host": benchmark_host("cpu"),
        "corpus": "tests/corpus",
        "category_filter": "pdf",
        "document_count": len(documents),
        "overall_percent": round(avg, 1),
        "avg_elapsed_seconds": round(elapsed, 4),
        "total_elapsed_seconds": round(sum(doc["elapsed_seconds"] for doc in documents), 4),
        "categories": {
            "pdf": {
                "document_count": len(documents),
                "overall_percent": round(avg, 1),
                "avg_elapsed_seconds": round(elapsed, 4),
                "total_elapsed_seconds": round(sum(doc["elapsed_seconds"] for doc in documents), 4),
                "failed_count": sum(1 for doc in documents if doc.get("error")),
            }
        },
        "documents": documents,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"Overall: {avg:.1f}% ({len(documents)} documents, {elapsed:.3f}s avg/document)")
    print(f"JSON report: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
