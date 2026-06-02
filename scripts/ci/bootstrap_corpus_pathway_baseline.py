#!/usr/bin/env python3
"""Bootstrap corpus pathway baselines from benchmark result JSON files."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


BASELINE = Path("docs/release/corpus_pathway_baseline.json")


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise SystemExit(f"error: missing file: {path}")
    except json.JSONDecodeError as exc:
        raise SystemExit(f"error: invalid JSON in {path}: {exc}")


def is_expected_blocked(document: dict) -> bool:
    status = document.get("status")
    if status == "expected_blocked":
        return True
    message = " ".join(
        str(value)
        for value in (document.get("error"), document.get("blocked_reason"))
        if value
    ).lower()
    return "password" in message and any(term in message for term in ("protected", "required", "encrypted"))


def is_environment_blocked(document: dict) -> bool:
    message = " ".join(
        str(value)
        for value in (document.get("error"), document.get("blocked_reason"))
        if value
    ).lower()
    return (
        "metal device" in message
        or "no metal" in message
        or "device compatibility" in message
        or "couldn't run on this mac" in message
    )


def baseline_for_document(document: dict) -> dict:
    if is_expected_blocked(document):
        return {
            "status": "expected_blocked",
            "blocked_reason": document.get("blocked_reason") or "password_required",
        }
    if is_environment_blocked(document):
        return {
            "status": "environment_blocked",
            "blocked_reason": "metal_unavailable",
        }

    status = document.get("status") or ("failed" if document.get("error") else "scored")
    return {
        "status": status,
        "overall_percent": float(document.get("overall_percent", 0)),
        "elapsed_seconds": float(document.get("elapsed_seconds", 0)),
        "category": document.get("category"),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", default=str(BASELINE))
    parser.add_argument(
        "results",
        nargs="+",
        help="benchmark JSON files to use as the current document x pathway baseline",
    )
    args = parser.parse_args()

    baseline_path = Path(args.baseline)
    baseline = load_json(baseline_path)
    document_baselines = baseline.setdefault("document_baselines", {})
    source_reports = baseline.setdefault("source_reports", {})

    for result in args.results:
        result_path = Path(result)
        report = load_json(result_path)
        pathway = report.get("pathway")
        if not pathway:
            raise SystemExit(f"error: {result_path} missing pathway")

        documents = report.get("documents", [])
        if not documents:
            raise SystemExit(f"error: {result_path} has no documents")

        document_baselines[pathway] = {
            document["id"]: baseline_for_document(document)
            for document in documents
            if document.get("id")
        }
        source_reports[pathway] = str(result_path)

    baseline["baseline_state"] = "document-baseline"
    baseline_path.write_text(json.dumps(baseline, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"ok: bootstrapped {len(args.results)} pathway baseline(s) in {baseline_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
