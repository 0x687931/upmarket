#!/usr/bin/env python3
"""
Bootstrap HuggingFace dataset baseline thresholds from the first evaluation run.

Reads the three evaluation report JSON files and seeds initial thresholds.
These can then be tightened as the pipeline improves.

Usage:
  python3 scripts/ci/bootstrap_hf_baseline.py
"""

import json
import sys
from pathlib import Path


def extract_thresholds_from_reports(repo_root: Path) -> dict:
    """Extract threshold recommendations from evaluation reports."""
    reports_dir = repo_root / 'reports'

    thresholds = {}

    # PDFA: use 80% of achieved overall_percent
    pdfa_reports = sorted(reports_dir.glob('hf-pdfa-*.json'), reverse=True)
    if pdfa_reports:
        with open(pdfa_reports[0]) as f:
            pdfa_data = json.load(f)
            overall = pdfa_data.get('summary', {}).get('overall_percent', 90)
            avg_cer = pdfa_data.get('summary', {}).get('avg_cer', 0.1)
            heading_recall = pdfa_data.get('summary', {}).get('heading_recall_percent', 70)

            thresholds['pdfa'] = {
                'overall_percent': max(75, int(overall * 0.85)),  # Conservative: 85% of achieved
                'char_error_rate_max': round(min(0.10, avg_cer * 1.5), 4),
                'heading_recall_percent': max(60, int(heading_recall * 0.9))
            }

    # IDL: use 80% of achieved overall_percent
    idl_reports = sorted(reports_dir.glob('hf-idl-*.json'), reverse=True)
    if idl_reports:
        with open(idl_reports[0]) as f:
            idl_data = json.load(f)
            overall = idl_data.get('summary', {}).get('overall_percent', 70)
            artifacts = idl_data.get('summary', {}).get('avg_artifacts_per_doc', 2)

            thresholds['idl'] = {
                'overall_percent': max(60, int(overall * 0.85)),
                'artifact_penalty_max': int(artifacts * 1.5) + 1
            }

    # DocVQA: use 80% of achieved hit rate
    docvqa_reports = sorted(reports_dir.glob('hf-docvqa-*.json'), reverse=True)
    if docvqa_reports:
        with open(docvqa_reports[0]) as f:
            docvqa_data = json.load(f)
            qa_hit = docvqa_data.get('summary', {}).get('qa_hit_rate', 0.60)
            exact_match = docvqa_data.get('summary', {}).get('exact_match_rate', 0.40)

            thresholds['docvqa'] = {
                'qa_hit_rate': max(0.50, round(qa_hit * 0.85, 2)),
                'exact_match': max(0.30, round(exact_match * 0.85, 2))
            }

    return thresholds


def main():
    repo_root = Path(__file__).parent.parent.parent
    reports_dir = repo_root / 'reports'

    print("🌱 Bootstrap HuggingFace Dataset Baseline Thresholds")
    print("=" * 50)

    # Check if reports exist
    if not any(reports_dir.glob('hf-*.json')):
        print("❌ Error: No evaluation reports found in reports/")
        print("Run: bash scripts/datasets/benchmark_hf.sh --dataset all")
        return 1

    thresholds = extract_thresholds_from_reports(repo_root)

    if not thresholds:
        print("❌ Error: Could not extract thresholds from reports")
        return 1

    print("\n📊 Extracted thresholds:")
    for dataset, values in thresholds.items():
        print(f"  {dataset}:")
        for key, val in values.items():
            print(f"    {key}: {val}")

    # Write baseline file
    baseline = {
        "version": 1,
        "thresholds": thresholds
    }

    baseline_path = repo_root / 'docs' / 'release' / 'hf_dataset_baseline.json'
    baseline_path.parent.mkdir(parents=True, exist_ok=True)
    baseline_path.write_text(json.dumps(baseline, indent=2))

    print(f"\n✅ Baseline written: {baseline_path}")
    print("\nYou can now commit this file:")
    print(f"  git add docs/release/hf_dataset_baseline.json")
    print(f"  git commit -m 'Bootstrap HuggingFace dataset baseline thresholds'")

    return 0


if __name__ == "__main__":
    sys.exit(main())
