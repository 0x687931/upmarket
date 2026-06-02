#!/usr/bin/env python3
"""Generate the corpus document expected-status ledger from current baselines."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


MANIFEST = Path("tests/corpus/manifest.json")
BASELINE = Path("docs/release/corpus_pathway_baseline.json")
OUTPUT = Path("docs/release/corpus_expected_status.json")
DEGRADED_THRESHOLD_PERCENT = 70.0


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def document_rows(baseline: dict[str, Any]) -> dict[str, list[tuple[str, dict[str, Any]]]]:
    rows_by_document: dict[str, list[tuple[str, dict[str, Any]]]] = {}
    for pathway, rows in baseline.get("document_baselines", {}).items():
        for document_id, row in rows.items():
            rows_by_document.setdefault(document_id, []).append((pathway, row))
    return rows_by_document


def expected_status(rows: list[tuple[str, dict[str, Any]]]) -> tuple[str, str, float | None, str | None]:
    for _pathway, row in rows:
        if row.get("status") == "expected_blocked" and row.get("blocked_reason") == "password_required":
            return ("password_required", "password_required", None, "Document requires a password before conversion.")

    scored = [
        (pathway, float(row.get("overall_percent", 0)))
        for pathway, row in rows
        if row.get("status") == "scored"
    ]
    if not scored:
        return ("unsupported", "no_scored_pathway", None, "No current shipping pathway has scored output for this document.")

    best_pathway, best_score = max(scored, key=lambda item: item[1])
    if best_score < DEGRADED_THRESHOLD_PERCENT:
        return (
            "degraded_output",
            best_pathway,
            best_score,
            f"Best current pathway is below {DEGRADED_THRESHOLD_PERCENT:.0f}% quality threshold.",
        )
    return ("success", best_pathway, best_score, None)


def generate() -> dict[str, Any]:
    manifest = load_json(MANIFEST)
    baseline = load_json(BASELINE)
    rows_by_document = document_rows(baseline)

    documents = []
    counts: dict[str, int] = {}
    for document in manifest.get("documents", []):
        rows = rows_by_document.get(document["id"], [])
        status, source, score, note = expected_status(rows)
        counts[status] = counts.get(status, 0) + 1
        entry: dict[str, Any] = {
            "id": document["id"],
            "file": document["file"],
            "category": document["category"],
            "format": document["format"],
            "expected_status": status,
            "status_source": source,
        }
        if score is not None:
            entry["best_overall_percent"] = round(score, 1)
        if note:
            entry["note"] = note
        documents.append(entry)

    return {
        "version": 1,
        "manifest": str(MANIFEST),
        "pathway_baseline": str(BASELINE),
        "degraded_threshold_percent": DEGRADED_THRESHOLD_PERCENT,
        "allowed_statuses": ["degraded_output", "password_required", "success", "unsupported"],
        "counts": dict(sorted(counts.items())),
        "documents": documents,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail if the existing ledger is stale")
    parser.add_argument("--output", default=str(OUTPUT))
    args = parser.parse_args()

    generated = json.dumps(generate(), indent=2, sort_keys=True) + "\n"
    output = Path(args.output)
    if args.check:
        current = output.read_text(encoding="utf-8")
        if current != generated:
            raise SystemExit(f"error: {output} is stale; rerun scripts/ci/generate_corpus_expected_status.py")
        print(f"ok: {output} is current")
        return 0

    output.write_text(generated, encoding="utf-8")
    print(f"ok: wrote {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
