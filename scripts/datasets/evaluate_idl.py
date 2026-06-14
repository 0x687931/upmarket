#!/usr/bin/env python3
"""
Evaluate IDL dataset OCR quality.

IDL contains scanned industrial documents without ground truth.
Scores are based on OCR confidence, artifact detection, and structural completeness.
"""

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional


def load_manifest(manifest_path: Path) -> List[Dict[str, Any]]:
    """Load manifest.json."""
    if not manifest_path.exists():
        raise FileNotFoundError(f"Manifest not found: {manifest_path}")
    return json.loads(manifest_path.read_text())


def count_artifacts(text: str) -> int:
    """Count OCR artifacts in extracted text."""
    artifacts = 0
    # Replacement char (often from OCR failures)
    artifacts += text.count('�')
    # Soft hyphens
    artifacts += text.count('­')
    # Isolated ligatures
    artifacts += text.count('ﬁ') + text.count('ﬂ') + text.count('ﬀ')
    return artifacts


def evaluate_idl(manifest_path: Path, repo_root: Path) -> Dict[str, Any]:
    """Evaluate IDL dataset."""
    manifest = load_manifest(manifest_path)

    results = {
        "dataset": "idl",
        "timestamp": datetime.now().isoformat(),
        "manifest_count": len(manifest),
        "documents": [],
        "summary": {}
    }

    confidence_scores = []
    artifact_counts = []
    coverage_scores = []
    errors = []

    for doc in manifest:
        doc_id = doc['id']
        file_path = repo_root / doc['file']

        print(f"  {doc_id}...", end=" ", flush=True)

        doc_result = {
            "id": doc_id,
            "file": doc['file'],
            "ocr_confidence": None,
            "artifacts": 0,
            "coverage": None,
            "error": None
        }

        try:
            if not file_path.exists():
                raise FileNotFoundError(f"File not found: {file_path}")

            # In real usage, this would invoke Vision OCR or Docling scanned pipeline
            # and extract the metadata.extractionConfidence from DocumentMetadata
            # For now, placeholder with expected structure
            extracted_text = ""
            ocr_confidence = 0.0

            # Count artifacts
            artifacts = count_artifacts(extracted_text)
            artifact_counts.append(artifacts)

            # Estimate coverage from text length
            coverage = min(1.0, len(extracted_text.split()) / 50.0)  # rough heuristic
            coverage_scores.append(coverage)

            doc_result["ocr_confidence"] = round(ocr_confidence, 3)
            doc_result["artifacts"] = artifacts
            doc_result["coverage"] = round(coverage, 3)

            confidence_scores.append(ocr_confidence)

            print("✓")

        except Exception as e:
            doc_result["error"] = str(e)
            errors.append((doc_id, str(e)))
            print(f"✗ ({e})")

        results["documents"].append(doc_result)

    # Summary statistics
    if confidence_scores:
        results["summary"] = {
            "total_documents": len(manifest),
            "successful": len(confidence_scores),
            "failed": len(errors),
            "avg_ocr_confidence": round(sum(confidence_scores) / len(confidence_scores), 3),
            "min_ocr_confidence": round(min(confidence_scores), 3),
            "max_ocr_confidence": round(max(confidence_scores), 3),
            "total_artifacts": sum(artifact_counts),
            "avg_artifacts_per_doc": round(sum(artifact_counts) / len(artifact_counts), 1),
            "avg_coverage": round(sum(coverage_scores) / len(coverage_scores), 3),
            "overall_percent": round(sum(confidence_scores) / len(confidence_scores) * 100, 1)
        }

    return results


def main():
    parser = argparse.ArgumentParser(description="Evaluate IDL dataset OCR quality")
    parser.add_argument('--manifest', type=Path, default=None,
                        help='Path to manifest file (auto-resolved if not provided)')
    parser.add_argument('--output', type=Path, default=None,
                        help='Output JSON file (default: reports/hf-idl-<timestamp>.json)')

    args = parser.parse_args()

    repo_root = Path(__file__).parent.parent.parent
    manifest_path = args.manifest or repo_root / "tests" / "datasets" / "manifests" / "hf_idl_manifest.json"

    if not manifest_path.exists():
        print(f"Error: manifest not found at {manifest_path}")
        print("Run: python3 scripts/datasets/prepare_hf_corpus.py --dataset idl")
        sys.exit(1)

    print(f"📊 Evaluating IDL dataset: {manifest_path}")

    results = evaluate_idl(manifest_path, repo_root)

    # Write results
    output_path = args.output or repo_root / "reports" / f"hf-idl-{datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(results, indent=2))

    print(f"\n✓ Results: {output_path}")
    print(f"  Overall: {results['summary'].get('overall_percent', 'N/A')}%")
    print(f"  Avg OCR confidence: {results['summary'].get('avg_ocr_confidence', 'N/A')}")
    print(f"  Artifacts: {results['summary'].get('total_artifacts', 0)}")


if __name__ == "__main__":
    main()
