#!/usr/bin/env python3
"""Validate the corpus document expected-status ledger."""

from __future__ import annotations

import json
import sys
from pathlib import Path


MANIFEST = Path("tests/corpus/manifest.json")
LEDGER = Path("docs/release/corpus_expected_status.json")
ALLOWED = {"success", "unsupported", "password_required", "degraded_output"}


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise SystemExit(f"error: missing file: {path}")
    except json.JSONDecodeError as error:
        raise SystemExit(f"error: invalid JSON in {path}: {error}")


def main() -> int:
    manifest = load_json(MANIFEST)
    ledger = load_json(LEDGER)
    manifest_documents = {document["id"]: document for document in manifest.get("documents", [])}
    ledger_documents = ledger.get("documents", [])
    errors: list[str] = []

    if ledger.get("manifest") != str(MANIFEST):
        errors.append(f"{LEDGER}: manifest must be {MANIFEST}")
    if ledger.get("allowed_statuses") != sorted(ALLOWED):
        errors.append(f"{LEDGER}: allowed_statuses must be {sorted(ALLOWED)}")

    seen: set[str] = set()
    counts = dict.fromkeys(ALLOWED, 0)
    for entry in ledger_documents:
        document_id = entry.get("id")
        if document_id in seen:
            errors.append(f"{LEDGER}: duplicate document id {document_id}")
            continue
        seen.add(document_id)

        manifest_entry = manifest_documents.get(document_id)
        if manifest_entry is None:
            errors.append(f"{LEDGER}: unknown document id {document_id}")
            continue
        for key in ("file", "category", "format"):
            if entry.get(key) != manifest_entry.get(key):
                errors.append(f"{document_id}: {key} changed from manifest")

        status = entry.get("expected_status")
        if status not in ALLOWED:
            errors.append(f"{document_id}: invalid expected_status {status!r}")
            continue
        counts[status] += 1
        if status == "degraded_output" and float(entry.get("best_overall_percent", 0)) >= float(ledger.get("degraded_threshold_percent", 70)):
            errors.append(f"{document_id}: degraded_output must be below degraded threshold")
        if status == "success" and float(entry.get("best_overall_percent", 0)) < float(ledger.get("degraded_threshold_percent", 70)):
            errors.append(f"{document_id}: success must meet degraded threshold")

    missing = sorted(set(manifest_documents) - seen)
    if missing:
        errors.append(f"{LEDGER}: missing {len(missing)} document(s): {', '.join(missing[:10])}")

    compact_counts = {key: value for key, value in counts.items() if value}
    if ledger.get("counts") != dict(sorted(compact_counts.items())):
        errors.append(f"{LEDGER}: counts are stale")

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1
    print("ok: corpus expected statuses cover every manifest document")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
