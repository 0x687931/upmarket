#!/usr/bin/env python3
"""Create a Markdown comparison from corpus pathway benchmark JSON reports."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def load_report(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def markdown_cell(value: str) -> str:
    return value.replace("|", "\\|").replace("\n", " ")


def score_cell(document: dict | None) -> str:
    if document is None:
        return "-"
    if document.get("error"):
        return "ERR"
    return f"{float(document.get('overall_percent', 0)):.1f}%"


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
        "## Document Score Matrix",
        "",
        "Scores are overall percentages. `ERR` means the pathway ran and failed for that file. `-` means that converter was not run for that file.",
        "",
    ])

    document_rows: dict[str, dict] = {}
    for report in reports_by_pathway.values():
        for document in report.get("documents", []):
            doc_id = document.get("id", "")
            if not doc_id:
                continue
            row = document_rows.setdefault(doc_id, {
                "id": doc_id,
                "file": document.get("file") or doc_id,
                "category": document.get("category", ""),
                "scores": {},
            })
            if document.get("file"):
                row["file"] = document["file"]
            if document.get("category"):
                row["category"] = document["category"]
            pathway = report.get("pathway") or report.get("pipeline", "")
            row["scores"][pathway] = document

    if document_rows:
        run_pathways = sorted(reports_by_pathway)
        lines.append("| File | Category | " + " | ".join(run_pathways) + " |")
        lines.append("| --- | --- | " + " | ".join("---:" for _ in run_pathways) + " |")
        for row in sorted(document_rows.values(), key=lambda item: (item["category"], item["file"], item["id"])):
            cells = [
                markdown_cell(row["file"]),
                markdown_cell(row["category"]),
            ]
            cells.extend(score_cell(row["scores"].get(pathway)) for pathway in run_pathways)
            lines.append("| " + " | ".join(cells) + " |")
        lines.append("")

    lines.extend([
        "## Document-Level Data",
        "",
        "Use the JSON reports in the same artifact for component scores, elapsed time, errors, regression review, and uplift review.",
        "",
    ])

    args.output.write_text("\n".join(lines), encoding="utf-8")
    print(f"ok: wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
