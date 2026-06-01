#!/usr/bin/env python3
"""Create a Markdown comparison from corpus pathway benchmark JSON reports."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def load_report(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("reports", nargs="+", type=Path)
    parser.add_argument("--pathways", type=Path, default=Path("docs/release/conversion_pathways.json"))
    parser.add_argument("--output", type=Path, default=Path("reports/corpus-pathway-comparison.md"))
    args = parser.parse_args()

    reports = [load_report(path) for path in args.reports if path.exists()]
    pathways = {}
    if args.pathways.exists():
        pathways = load_report(args.pathways).get("pathways", {})
    reports_by_pathway = {
        report.get("pathway") or report.get("pipeline", ""): report
        for report in reports
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)

    lines = [
        "# Corpus Pathway Benchmark Comparison",
        "",
        "This report compares convert-to-Markdown quality by pathway. Shipping decisions use the stored baseline ledger; internal reference pathways are evidence only and do not imply approval to ship those dependencies.",
        "",
        "## Pathway Summary",
        "",
        "| Pathway | Status | Pipeline | Documents | Overall | Failed |",
        "| --- | --- | --- | ---: | ---: | ---: |",
    ]

    pathway_ids = sorted(set(pathways) | set(reports_by_pathway))
    for pathway_id in pathway_ids:
        report = reports_by_pathway.get(pathway_id)
        config = pathways.get(pathway_id, {})
        status = config.get("release_status", "unknown")
        if report is None:
            lines.append(f"| {pathway_id} | {status} | not run | 0 | - | - |")
            continue
        failed = sum(int(category.get("failed_count", 0)) for category in report.get("categories", {}).values())
        lines.append(
            f"| {pathway_id} | {status} | {report.get('pipeline', '-')} | "
            f"{report.get('document_count', 0)} | {float(report.get('overall_percent', 0)):.1f}% | {failed} |"
        )

    lines.extend(["", "## Category Summary", ""])
    for pathway, report in sorted(reports_by_pathway.items()):
        lines.extend([
            f"### {pathway}",
            "",
            "| Category | Documents | Overall | Failed |",
            "| --- | ---: | ---: | ---: |",
        ])
        for category, values in sorted(report.get("categories", {}).items()):
            lines.append(
                f"| {category} | {values.get('document_count', 0)} | "
                f"{float(values.get('overall_percent', 0)):.1f}% | {values.get('failed_count', 0)} |"
            )
        lines.append("")

    lines.extend([
        "## Document-Level Data",
        "",
        "Use the JSON reports in the same artifact for document-level regression and uplift review.",
        "",
    ])

    args.output.write_text("\n".join(lines), encoding="utf-8")
    print(f"ok: wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
