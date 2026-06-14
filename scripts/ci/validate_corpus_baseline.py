#!/usr/bin/env python3
"""Validate the release corpus baseline and optional benchmark results."""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path


BASELINE = Path("docs/release/corpus_baseline.json")
MANIFEST = Path("tests/corpus/manifest.json")


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise SystemExit(f"error: missing file: {path}")
    except json.JSONDecodeError as exc:
        raise SystemExit(f"error: invalid JSON in {path}: {exc}")


def validate_baseline(baseline: dict, manifest: dict) -> list[str]:
    errors: list[str] = []
    docs = manifest.get("documents", [])
    expected_count = baseline.get("corpus", {}).get("document_count")
    if expected_count != len(docs):
        errors.append(f"baseline document_count={expected_count} but manifest has {len(docs)} document(s)")

    # The manifest groups documents by `format` (asciidoc, docx, html, …); the baseline's
    # corpus.categories mirrors that distribution. (Earlier manifests used a `category`
    # field that no longer exists after the Document+GroundTruth corpus restructuring.)
    actual_categories = Counter(doc.get("format", "unknown") for doc in docs)
    expected_categories = baseline.get("corpus", {}).get("categories", {})
    if dict(sorted(actual_categories.items())) != dict(sorted(expected_categories.items())):
        errors.append(f"baseline categories do not match manifest: expected={expected_categories} actual={dict(sorted(actual_categories.items()))}")

    pipelines = baseline.get("pipelines", {})
    for name, config in pipelines.items():
        if "minimum_overall_percent" not in config:
            errors.append(f"pipeline {name} missing minimum_overall_percent")
        category_scores = config.get("minimum_category_percent")
        if not isinstance(category_scores, dict) or not category_scores:
            errors.append(f"pipeline {name} missing minimum_category_percent")

    return errors


def validate_results(baseline: dict, results: dict) -> list[str]:
    errors: list[str] = []
    pipeline = results.get("pipeline")
    if not pipeline:
        errors.append("benchmark results missing pipeline")
        return errors

    pipeline_baseline = baseline.get("pipelines", {}).get(pipeline)
    if not pipeline_baseline:
        errors.append(f"no baseline exists for pipeline: {pipeline}")
        return errors

    actual_doc_count = int(results.get("document_count", 0))
    expected_doc_count = int(baseline.get("corpus", {}).get("document_count", 0))
    if actual_doc_count < expected_doc_count:
        errors.append(f"{pipeline}: benchmark covered {actual_doc_count} document(s), baseline requires {expected_doc_count}")

    actual_overall = float(results.get("overall_percent", 0))
    minimum_overall = float(pipeline_baseline["minimum_overall_percent"])
    if actual_overall < minimum_overall:
        errors.append(f"{pipeline}: overall {actual_overall:.1f}% below baseline {minimum_overall:.1f}%")

    categories = results.get("categories", {})
    total_failed = sum(int(category.get("failed_count", 0)) for category in categories.values())
    maximum_failed = int(pipeline_baseline.get("maximum_failed_documents", 0))
    if total_failed > maximum_failed:
        errors.append(f"{pipeline}: {total_failed} failed document(s), baseline allows {maximum_failed}")

    maximum_category_failures = pipeline_baseline.get("maximum_category_failed_documents", {})
    for category, maximum in maximum_category_failures.items():
        actual_failed = int(categories.get(category, {}).get("failed_count", 0))
        if actual_failed > int(maximum):
            errors.append(f"{pipeline}: category {category} has {actual_failed} failed document(s), baseline allows {maximum}")

    for category, minimum in pipeline_baseline.get("minimum_category_percent", {}).items():
        actual = categories.get(category, {}).get("overall_percent")
        if actual is None:
            errors.append(f"{pipeline}: missing category result for {category}")
            continue
        if float(actual) < float(minimum):
            errors.append(f"{pipeline}: category {category} {float(actual):.1f}% below baseline {float(minimum):.1f}%")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", default=str(BASELINE))
    parser.add_argument("--manifest", default=str(MANIFEST))
    parser.add_argument("--results", help="optional benchmark JSON produced by scripts/benchmark.sh --json-output")
    args = parser.parse_args()

    baseline = load_json(Path(args.baseline))
    manifest = load_json(Path(args.manifest))
    errors = validate_baseline(baseline, manifest)

    if args.results:
        errors.extend(validate_results(baseline, load_json(Path(args.results))))

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    message = "ok: corpus baseline matches manifest"
    if args.results:
        message += f" and {args.results} passes baseline"
    print(message)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
