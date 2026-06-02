#!/usr/bin/env python3
"""Benchmark Apple-native metadata routes against the corpus."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import uuid
from pathlib import Path

from benchmark_scorer import benchmark_host, score_document


def build_runner() -> Path:
    build_dir = Path("build")
    build_dir.mkdir(exist_ok=True)
    binary = build_dir / f"benchmark-native-metadata-{uuid.uuid4().hex}"
    subprocess.run(
        [
            "xcrun",
            "swiftc",
            "-parse-as-library",
            "-module-cache-path",
            str(build_dir / "swift-module-cache"),
            "scripts/benchmark_native_metadata.swift",
            "-o",
            str(binary),
        ],
        check=True,
    )
    return binary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pathway", required=True, choices=["swift-imageio-metadata", "swift-avfoundation-metadata"])
    parser.add_argument("--json-output", required=True)
    args = parser.parse_args()

    binary = build_runner()
    try:
        proc = subprocess.run([str(binary), args.pathway], check=True, capture_output=True, text=True)
    finally:
        binary.unlink(missing_ok=True)

    documents = []
    categories: dict[str, dict[str, float]] = {}
    for line in proc.stdout.splitlines():
        row = json.loads(line)
        if row.get("error"):
            score = score_document("", row, None)
            score.error = row["error"]
        else:
            score = score_document(row["markdown"], row, None)
        score.file = row["file"]
        score.elapsed_seconds = float(row.get("elapsed_seconds") or 0)
        document = {
            "id": score.doc_id,
            "file": score.file,
            "category": score.category,
            "status": "failed" if score.error else "scored",
            "error": score.error,
            "heading_recall_percent": round(score.heading_recall * 100, 1),
            "table_accuracy_percent": round(score.table_accuracy * 100, 1),
            "content_completeness_percent": round(score.content_completeness * 100, 1),
            "overall_percent": round(score.overall * 100, 1),
            "markdown_valid": score.markdown_valid,
            "artifacts_found": score.artifacts_found,
            "elapsed_seconds": round(score.elapsed_seconds, 4),
        }
        documents.append(document)

        category = categories.setdefault(score.category, {"count": 0, "failed": 0, "overall": 0.0, "elapsed": 0.0})
        category["count"] += 1
        category["failed"] += 1 if score.error else 0
        category["overall"] += score.overall * 100
        category["elapsed"] += score.elapsed_seconds

    category_summary = {
        name: {
            "document_count": int(values["count"]),
            "failed_count": int(values["failed"]),
            "overall_percent": round(values["overall"] / values["count"], 1) if values["count"] else 0,
            "avg_elapsed_seconds": round(values["elapsed"] / values["count"], 4) if values["count"] else 0,
        }
        for name, values in sorted(categories.items())
    }
    report = {
        "pathway": args.pathway,
        "pipeline": "fast",
        "corpus": "tests/corpus",
        "document_count": len(documents),
        "failed_count": sum(1 for document in documents if document["error"]),
        "overall_percent": round(
            sum(float(document["overall_percent"]) for document in documents) / len(documents),
            1,
        ) if documents else 0,
        "avg_elapsed_seconds": round(
            sum(float(document["elapsed_seconds"]) for document in documents) / len(documents),
            4,
        ) if documents else 0,
        "benchmark_host": benchmark_host("auto"),
        "categories": category_summary,
        "documents": documents,
    }

    output = Path(args.json_output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        f"Overall: {report['overall_percent']:.1f}% "
        f"({report['document_count']} documents, {report['failed_count']} failed)"
    )
    print(f"JSON report: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
