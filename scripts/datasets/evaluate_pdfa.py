#!/usr/bin/env python3
"""
Evaluate PDFA text fidelity against embedded PDF text ground truth.

Scores extracted markdown against the embedded text using word error rate,
character error rate, and content completeness metrics.
"""

import argparse
import json
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

try:
    import editdistance
except ImportError:
    print("Error: editdistance package not installed.")
    print("Install with: pip install editdistance")
    sys.exit(1)


def load_manifest(manifest_path: Path) -> List[Dict[str, Any]]:
    """Load manifest.json."""
    if not manifest_path.exists():
        raise FileNotFoundError(f"Manifest not found: {manifest_path}")
    return json.loads(manifest_path.read_text())


def extract_text_from_pdf(pdf_path: Path) -> str:
    """Extract text from PDF (requires conversion runner to be invoked)."""
    # In real usage, this would call the Upmarket conversion pipeline
    # For now, placeholder that would be replaced with actual pipeline invocation
    return ""


def normalize_text(text: str) -> str:
    """Normalize text for comparison."""
    return ' '.join(text.split())


def compute_word_error_rate(ref: str, hyp: str) -> float:
    """Compute WER between reference and hypothesis."""
    ref_words = normalize_text(ref).split()
    hyp_words = normalize_text(hyp).split()

    if not ref_words:
        return 1.0 if hyp_words else 0.0

    dist = editdistance.eval(ref_words, hyp_words)
    return dist / len(ref_words)


def compute_char_error_rate(ref: str, hyp: str) -> float:
    """Compute CER between reference and hypothesis."""
    ref_norm = normalize_text(ref)
    hyp_norm = normalize_text(hyp)

    if not ref_norm:
        return 1.0 if hyp_norm else 0.0

    dist = editdistance.eval(ref_norm, hyp_norm)
    return dist / len(ref_norm)


def compute_content_completeness(ref: str, hyp: str) -> float:
    """Compute content completeness: how much of reference is in hypothesis."""
    ref_words = set(normalize_text(ref).split())
    hyp_words = set(normalize_text(hyp).split())

    if not ref_words:
        return 1.0

    overlap = len(ref_words & hyp_words)
    return overlap / len(ref_words)


def evaluate_pdfa(manifest_path: Path, repo_root: Path) -> Dict[str, Any]:
    """Evaluate PDFA dataset."""
    manifest = load_manifest(manifest_path)

    results = {
        "dataset": "pdfa",
        "timestamp": datetime.now().isoformat(),
        "manifest_count": len(manifest),
        "documents": [],
        "summary": {}
    }

    cer_scores = []
    wer_scores = []
    completeness_scores = []
    errors = []

    for doc in manifest:
        doc_id = doc['id']
        file_path = repo_root / doc['file']
        gt_path = repo_root / doc['ground_truth']

        print(f"  {doc_id}...", end=" ", flush=True)

        doc_result = {
            "id": doc_id,
            "file": doc['file'],
            "cer": None,
            "wer": None,
            "completeness": None,
            "error": None
        }

        try:
            # Load ground truth
            if not gt_path.exists():
                raise FileNotFoundError(f"Ground truth not found: {gt_path}")

            ground_truth = gt_path.read_text(encoding='utf-8', errors='ignore')

            # Extract from PDF (placeholder — would use actual pipeline)
            extracted = extract_text_from_pdf(file_path)
            if not extracted:
                raise ValueError("Could not extract text from PDF")

            # Compute metrics
            cer = compute_char_error_rate(ground_truth, extracted)
            wer = compute_word_error_rate(ground_truth, extracted)
            completeness = compute_content_completeness(ground_truth, extracted)

            doc_result["cer"] = round(cer, 4)
            doc_result["wer"] = round(wer, 4)
            doc_result["completeness"] = round(completeness, 4)

            cer_scores.append(cer)
            wer_scores.append(wer)
            completeness_scores.append(completeness)

            print("✓")

        except Exception as e:
            doc_result["error"] = str(e)
            errors.append((doc_id, str(e)))
            print(f"✗ ({e})")

        results["documents"].append(doc_result)

    # Summary statistics
    if cer_scores:
        results["summary"] = {
            "total_documents": len(manifest),
            "successful": len(cer_scores),
            "failed": len(errors),
            "avg_cer": round(sum(cer_scores) / len(cer_scores), 4),
            "min_cer": round(min(cer_scores), 4),
            "max_cer": round(max(cer_scores), 4),
            "avg_wer": round(sum(wer_scores) / len(wer_scores), 4),
            "avg_completeness": round(sum(completeness_scores) / len(completeness_scores), 4),
            "overall_percent": round((1 - sum(cer_scores) / len(cer_scores)) * 100, 1)
        }

    return results


def main():
    parser = argparse.ArgumentParser(description="Evaluate PDFA dataset text fidelity")
    parser.add_argument('--manifest', type=Path, default=None,
                        help='Path to manifest file (auto-resolved if not provided)')
    parser.add_argument('--output', type=Path, default=None,
                        help='Output JSON file (default: reports/hf-pdfa-<timestamp>.json)')

    args = parser.parse_args()

    repo_root = Path(__file__).parent.parent.parent
    manifest_path = args.manifest or repo_root / "tests" / "datasets" / "manifests" / "hf_pdfa_manifest.json"

    if not manifest_path.exists():
        print(f"Error: manifest not found at {manifest_path}")
        print("Run: python3 scripts/datasets/prepare_hf_corpus.py --dataset pdfa")
        sys.exit(1)

    print(f"📊 Evaluating PDFA dataset: {manifest_path}")

    results = evaluate_pdfa(manifest_path, repo_root)

    # Write results
    output_path = args.output or repo_root / "reports" / f"hf-pdfa-{datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(results, indent=2))

    print(f"\n✓ Results: {output_path}")
    print(f"  Overall: {results['summary'].get('overall_percent', 'N/A')}%")
    print(f"  Avg CER: {results['summary'].get('avg_cer', 'N/A')}")
    print(f"  Avg completeness: {results['summary'].get('avg_completeness', 'N/A')}")


if __name__ == "__main__":
    main()
