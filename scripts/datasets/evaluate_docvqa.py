#!/usr/bin/env python3
"""
Evaluate DocVQA dataset Q&A accuracy.

For each document image, extract text and check whether annotated answers
appear in the extracted text. Reports Q&A hit rate, exact match, and F1 score.
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


def normalize_answer(text: str) -> str:
    """Normalize answer for matching."""
    return ' '.join(text.lower().split())


def compute_f1(answer: str, extracted: str) -> float:
    """Compute F1 score between answer and extracted text (token overlap)."""
    answer_tokens = set(normalize_answer(answer).split())
    extracted_tokens = set(normalize_answer(extracted).split())

    if not answer_tokens or not extracted_tokens:
        return 1.0 if answer_tokens == extracted_tokens else 0.0

    common = len(answer_tokens & extracted_tokens)
    precision = common / len(extracted_tokens) if extracted_tokens else 0.0
    recall = common / len(answer_tokens) if answer_tokens else 0.0

    if precision + recall == 0:
        return 0.0

    return 2 * (precision * recall) / (precision + recall)


def answer_in_text(answer: str, extracted: str) -> bool:
    """Check if answer appears in extracted text (substring match)."""
    norm_answer = normalize_answer(answer)
    norm_extracted = normalize_answer(extracted)
    return norm_answer in norm_extracted


def evaluate_docvqa(manifest_path: Path, repo_root: Path) -> Dict[str, Any]:
    """Evaluate DocVQA dataset."""
    manifest = load_manifest(manifest_path)

    results = {
        "dataset": "docvqa",
        "timestamp": datetime.now().isoformat(),
        "manifest_count": len(manifest),
        "documents": [],
        "summary": {}
    }

    total_questions = 0
    answered_questions = 0
    exact_matches = 0
    f1_scores = []
    errors = []

    for doc in manifest:
        doc_id = doc['id']
        file_path = repo_root / doc['file']
        qa_pairs = doc.get('expected_qa', [])

        print(f"  {doc_id} ({len(qa_pairs)} Q&A)...", end=" ", flush=True)

        doc_result = {
            "id": doc_id,
            "file": doc['file'],
            "qa_count": len(qa_pairs),
            "qa_hit_rate": 0.0,
            "exact_match_rate": 0.0,
            "avg_f1": 0.0,
            "error": None
        }

        try:
            if not file_path.exists():
                raise FileNotFoundError(f"File not found: {file_path}")

            # In real usage, this would invoke Vision OCR and extract text
            # For now, placeholder
            extracted_text = ""

            # Evaluate each Q&A pair
            doc_f1_scores = []
            doc_answered = 0
            doc_exact = 0

            for qa in qa_pairs:
                question = qa.get('question', '')
                answer = qa.get('answer', '')

                if not answer:
                    continue

                total_questions += 1

                # Check if answer is in extracted text
                if answer_in_text(answer, extracted_text):
                    doc_answered += 1
                    answered_questions += 1

                    # Exact match: answer appears as continuous substring
                    if normalize_answer(answer) in normalize_answer(extracted_text):
                        doc_exact += 1
                        exact_matches += 1

                # F1 score (token overlap)
                f1 = compute_f1(answer, extracted_text)
                doc_f1_scores.append(f1)
                f1_scores.append(f1)

            # Document-level metrics
            if qa_pairs:
                doc_result["qa_hit_rate"] = round(doc_answered / len(qa_pairs), 3)
                doc_result["exact_match_rate"] = round(doc_exact / len(qa_pairs), 3)
                doc_result["avg_f1"] = round(sum(doc_f1_scores) / len(doc_f1_scores), 3) if doc_f1_scores else 0.0

            print("✓")

        except Exception as e:
            doc_result["error"] = str(e)
            errors.append((doc_id, str(e)))
            print(f"✗ ({e})")

        results["documents"].append(doc_result)

    # Summary statistics
    results["summary"] = {
        "total_documents": len(manifest),
        "successful": len(manifest) - len(errors),
        "failed": len(errors),
        "total_questions": total_questions,
        "answered_questions": answered_questions,
        "qa_hit_rate": round(answered_questions / total_questions, 3) if total_questions else 0.0,
        "exact_match_rate": round(exact_matches / total_questions, 3) if total_questions else 0.0,
        "avg_f1": round(sum(f1_scores) / len(f1_scores), 3) if f1_scores else 0.0,
        "overall_percent": round(answered_questions / total_questions * 100, 1) if total_questions else 0.0
    }

    return results


def main():
    parser = argparse.ArgumentParser(description="Evaluate DocVQA dataset Q&A accuracy")
    parser.add_argument('--manifest', type=Path, default=None,
                        help='Path to manifest file (auto-resolved if not provided)')
    parser.add_argument('--output', type=Path, default=None,
                        help='Output JSON file (default: reports/hf-docvqa-<timestamp>.json)')

    args = parser.parse_args()

    repo_root = Path(__file__).parent.parent.parent
    manifest_path = args.manifest or repo_root / "tests" / "datasets" / "manifests" / "hf_docvqa_manifest.json"

    if not manifest_path.exists():
        print(f"Error: manifest not found at {manifest_path}")
        print("Run: python3 scripts/datasets/prepare_hf_corpus.py --dataset docvqa")
        sys.exit(1)

    print(f"❓ Evaluating DocVQA dataset: {manifest_path}")

    results = evaluate_docvqa(manifest_path, repo_root)

    # Write results
    output_path = args.output or repo_root / "reports" / f"hf-docvqa-{datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(results, indent=2))

    print(f"\n✓ Results: {output_path}")
    print(f"  Q&A hit rate: {results['summary'].get('qa_hit_rate', 'N/A')}")
    print(f"  Exact match: {results['summary'].get('exact_match_rate', 'N/A')}")
    print(f"  Avg F1: {results['summary'].get('avg_f1', 'N/A')}")


if __name__ == "__main__":
    main()
