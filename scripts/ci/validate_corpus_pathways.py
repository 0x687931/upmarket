#!/usr/bin/env python3
"""Validate corpus conversion-pathway coverage and optional pathway results."""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter
from pathlib import Path


MANIFEST = Path("tests/corpus/manifest.json")
PATHWAYS = Path("docs/release/conversion_pathways.json")
BASELINE = Path("docs/release/corpus_pathway_baseline.json")


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise SystemExit(f"error: missing file: {path}")
    except json.JSONDecodeError as exc:
        raise SystemExit(f"error: invalid JSON in {path}: {exc}")


def validate_registry(manifest: dict, pathways_doc: dict, baseline: dict) -> list[str]:
    errors: list[str] = []
    docs = manifest.get("documents", [])
    pathways = pathways_doc.get("pathways", {})
    if not docs:
        errors.append("corpus manifest has no documents")
    if not pathways:
        errors.append("conversion pathway registry has no pathways")
        return errors

    # The corpus is format-keyed (Document + GroundTruth schema, no category field), and
    # conversion is native-only. Formats with no native engine are exempted via
    # unsupported_formats; every other corpus document must be covered by a shipping pathway.
    corpus_formats = Counter(doc.get("format", "unknown") for doc in docs)
    unsupported_formats = set(pathways_doc.get("unsupported_formats", []))

    for fmt in sorted(unsupported_formats - set(corpus_formats)):
        errors.append(f"unsupported_formats lists '{fmt}', which is not present in the corpus (remove the stale entry)")

    shipping_coverage = {doc.get("id"): [] for doc in docs}

    for pathway_id, config in pathways.items():
        valid_formats = set(config.get("valid_formats", []))

        runner = config.get("runner")
        if not runner:
            errors.append(f"{pathway_id}: runner is required")

        release_status = config.get("release_status")
        if release_status not in {"shipping", "internal-reference-only"}:
            errors.append(f"{pathway_id}: release_status must be shipping or internal-reference-only")

        if release_status == "shipping" and config.get("baseline_required") is not True:
            errors.append(f"{pathway_id}: shipping pathways must require a baseline")

        if release_status == "shipping" and not valid_formats:
            errors.append(f"{pathway_id}: shipping pathways must declare valid_formats")

        if "pymupdf" in pathway_id.lower() and release_status != "internal-reference-only":
            errors.append(f"{pathway_id}: PyMuPDF pathways must stay internal-reference-only")

        if release_status == "shipping":
            for doc in docs:
                if doc.get("format") in valid_formats:
                    shipping_coverage[doc.get("id")].append(pathway_id)

    for doc in docs:
        if not shipping_coverage[doc.get("id")] and doc.get("format") not in unsupported_formats:
            errors.append(
                f"{doc.get('id')}: no shipping pathway covers format '{doc.get('format')}' "
                "(add a pathway with that format in valid_formats, or list it in unsupported_formats)"
            )

    expected_manifest = str(MANIFEST)
    if baseline.get("manifest") != expected_manifest:
        errors.append(f"{BASELINE}: manifest must be {expected_manifest}")
    if baseline.get("pathways") != str(PATHWAYS):
        errors.append(f"{BASELINE}: pathways must be {PATHWAYS}")

    return errors


def validate_results(results: dict, baseline: dict) -> list[str]:
    errors: list[str] = []
    pathway = results.get("pathway")
    if not pathway:
        errors.append("pathway benchmark results missing pathway")
        return errors

    policy = baseline.get("policy", {})
    document_limit = float(policy.get("document_regression_block_percent", 5.0))
    large_limit = float(policy.get("large_regression_block_percent", 25.0))
    uplift_review = float(policy.get("uplift_review_percent", 3.0))
    speed_limit = float(policy.get("document_speed_regression_multiplier", 1.5))
    document_baselines = baseline.get("document_baselines", {})
    pathway_baseline = document_baselines.get(pathway, {})

    if not pathway_baseline:
        print(f"warning: no stored document baselines for {pathway}; bootstrap run cannot detect regressions", file=sys.stderr)
        return errors

    missing = []
    uplifts = []
    for result in results.get("documents", []):
        doc_id = result.get("id")
        expected = pathway_baseline.get(doc_id)
        if expected is None:
            missing.append(doc_id)
            continue
        actual_status = normalise_result_status(result)
        expected_status = expected.get("status", "scored")
        if actual_status != expected_status:
            errors.append(f"{pathway}/{doc_id}: status changed from {expected_status} to {actual_status}")
            continue
        if actual_status in {"expected_blocked", "environment_blocked"}:
            continue
        actual = float(result.get("overall_percent", 0))
        expected_score = float(expected.get("overall_percent", 0))
        expected_elapsed = expected.get("avg_elapsed_seconds", expected.get("elapsed_seconds"))
        actual_elapsed = result.get("elapsed_seconds")
        delta = actual - expected_score
        if delta <= -large_limit:
            errors.append(f"{pathway}/{doc_id}: large regression {delta:.1f}% from baseline {expected_score:.1f}% to {actual:.1f}%")
        elif delta <= -document_limit:
            errors.append(f"{pathway}/{doc_id}: regression {delta:.1f}% from baseline {expected_score:.1f}% to {actual:.1f}%")
        elif delta >= uplift_review:
            uplifts.append(f"{doc_id} +{delta:.1f}%")
        if expected_elapsed is not None and actual_elapsed is not None:
            expected_seconds = float(expected_elapsed)
            actual_seconds = float(actual_elapsed)
            if expected_seconds > 0 and actual_seconds > expected_seconds * speed_limit:
                errors.append(
                    f"{pathway}/{doc_id}: speed regression {actual_seconds:.3f}s from baseline {expected_seconds:.3f}s "
                    f"(limit {speed_limit:.2f}x)"
                )

    if missing:
        errors.append(f"{pathway}: missing stored baselines for {len(missing)} result document(s): {', '.join(missing[:10])}")
    if uplifts:
        print(f"uplift candidates for {pathway}: " + ", ".join(uplifts[:20]))

    return errors


def normalise_result_status(result: dict) -> str:
    status = result.get("status")
    if status and status not in {"failed", "error"}:
        return status
    message = " ".join(
        str(value)
        for value in (result.get("error"), result.get("blocked_reason"))
        if value
    ).lower()
    if "password" in message and any(term in message for term in ("protected", "required", "encrypted")):
        return "expected_blocked"
    if any(
        term in message
        for term in (
            "metal device",
            "no metal",
            "device compatibility",
            "couldn't run on this mac",
            "graphics processor",
        )
    ):
        return "environment_blocked"
    if result.get("error"):
        return "failed"
    return "scored"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", default=str(MANIFEST))
    parser.add_argument("--pathways", default=str(PATHWAYS))
    parser.add_argument("--baseline", default=str(BASELINE))
    parser.add_argument(
        "--results",
        action="append",
        default=[],
        help="optional pathway benchmark JSON produced by scripts/benchmark.sh --pathway; may be repeated",
    )
    args = parser.parse_args()

    manifest = load_json(Path(args.manifest))
    pathways = load_json(Path(args.pathways))
    baseline = load_json(Path(args.baseline))

    errors = validate_registry(manifest, pathways, baseline)
    for result_path in args.results:
        errors.extend(validate_results(load_json(Path(result_path)), baseline))

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print("ok: corpus conversion pathways are covered and release exclusions hold")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
