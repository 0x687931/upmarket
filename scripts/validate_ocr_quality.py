#!/usr/bin/env python3
"""
Comprehensive quality validation against ground truth.

Measures:
- OCR Accuracy (CER/WER) against ground truth text
- Handwriting Detection accuracy
- Metadata extraction accuracy (language, extraction method)
- Overall workflow quality metrics
"""

import argparse
import json
import os
import sys
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Optional

# Add UpmarketPython to path
ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT / "UpmarketPython"))

# Configure security for corpus access
os.environ["UPMARKET_ALLOWED_INPUT_ROOTS"] = str(ROOT / "tests" / "corpus_test")


def edit_distance(s1: str, s2: str) -> int:
    """Calculate Levenshtein distance between two strings."""
    if len(s1) < len(s2):
        return edit_distance(s2, s1)
    if len(s2) == 0:
        return len(s1)
    
    previous_row = range(len(s2) + 1)
    for i, c1 in enumerate(s1):
        current_row = [i + 1]
        for j, c2 in enumerate(s2):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row.append(min(insertions, deletions, substitutions))
        previous_row = current_row
    
    return previous_row[-1]


def calculate_cer(extracted: str, ground_truth: str) -> float:
    """Calculate Character Error Rate."""
    if len(ground_truth) == 0:
        return 0.0 if len(extracted) == 0 else 1.0
    distance = edit_distance(extracted, ground_truth)
    return distance / len(ground_truth)


def calculate_wer(extracted: str, ground_truth: str) -> float:
    """Calculate Word Error Rate."""
    extracted_words = extracted.split()
    gt_words = ground_truth.split()
    
    if len(gt_words) == 0:
        return 0.0 if len(extracted_words) == 0 else 1.0
    
    distance = edit_distance(extracted_words, gt_words)
    return distance / len(gt_words)


@dataclass
class OcrQualityResult:
    """Results from OCR quality validation."""
    image_path: str
    ground_truth_path: str
    ground_truth_text: str
    extracted_text: str
    
    # Accuracy metrics
    cer: float = 0.0  # Character Error Rate
    wer: float = 0.0  # Word Error Rate
    
    # Confidence metrics
    extraction_confidence: Optional[float] = None
    
    # Handwriting metrics
    handwriting_ratio: float = 0.0
    contains_handwriting: bool = False
    
    # Metadata
    extraction_method: Optional[str] = None
    language: Optional[str] = None
    
    # Status
    success: bool = False
    error_message: Optional[str] = None


def validate_ocr_line(line_image_path: Path, gt_path: Path) -> OcrQualityResult:
    """Validate OCR quality on a line image against ground truth."""
    result = OcrQualityResult(
        image_path=str(line_image_path),
        ground_truth_path=str(gt_path),
        ground_truth_text="",
        extracted_text=""
    )
    
    try:
        # Read ground truth
        gt_text = gt_path.read_text(encoding='utf-8', errors='ignore').strip()
        result.ground_truth_text = gt_text
        
        # Convert image to text
        from docling_bridge.converter import convert
        
        output = convert(str(line_image_path))
        if output is None or not output.get("success", False):
            result.error_message = output.get("error", "Conversion failed") if output else "No output"
            return result
        
        # Extract text
        markdown = output.get("markdown", "").strip()
        result.extracted_text = markdown
        
        # Extract metadata
        metadata = output.get("metadata", {})
        if metadata:
            result.extraction_method = metadata.get("extraction_method", "unknown")
            result.language = metadata.get("language", None)
        
        # Calculate accuracy metrics
        result.cer = calculate_cer(markdown, gt_text)
        result.wer = calculate_wer(markdown, gt_text)
        
        result.success = True
        
    except Exception as e:
        result.error_message = str(e)
    
    return result


def validate_corpus(corpus_dir: Path, dataset_name: str, limit: Optional[int] = None):
    """Validate OCR quality across a corpus."""
    print(f"\n📊 Validating {dataset_name}")
    print("=" * 70)
    
    # Find line-level test images and their ground truth
    line_images = sorted(corpus_dir.glob("*_*.png"))
    if limit:
        line_images = line_images[:limit]
    
    if not line_images:
        print(f"⚠️  No line-level images found")
        return []
    
    print(f"Found {len(line_images)} line images to validate")
    print()
    
    results = []
    for i, img_path in enumerate(line_images, 1):
        # Find corresponding ground truth
        gt_path = img_path.with_suffix('.gt.txt')
        if not gt_path.exists():
            print(f"[{i}/{len(line_images)}] {img_path.name}... ⚠️  No GT")
            continue
        
        print(f"[{i}/{len(line_images)}] {img_path.name}...", end=" ", flush=True)
        result = validate_ocr_line(img_path, gt_path)
        results.append(result)
        
        if result.success:
            print(f"✓ CER: {result.cer:.3f} WER: {result.wer:.3f}")
        else:
            print(f"✗ {result.error_message[:40]}")
    
    return results


def print_summary(results: list[OcrQualityResult], dataset_name: str):
    """Print quality summary."""
    if not results:
        return
    
    successful = [r for r in results if r.success]
    if not successful:
        print(f"\n❌ No successful validations for {dataset_name}")
        return
    
    # Calculate metrics
    avg_cer = sum(r.cer for r in successful) / len(successful)
    avg_wer = sum(r.wer for r in successful) / len(successful)
    
    # CER interpretation
    if avg_cer < 0.01:
        cer_quality = "🟢 Excellent (< 1%)"
    elif avg_cer < 0.05:
        cer_quality = "🟡 Good (1-5%)"
    elif avg_cer < 0.10:
        cer_quality = "🟠 Fair (5-10%)"
    else:
        cer_quality = "🔴 Poor (> 10%)"
    
    print(f"\n📈 {dataset_name} Quality Metrics")
    print("─" * 70)
    print(f"Successful conversions: {len(successful)}/{len(results)} ({100*len(successful)//len(results)}%)")
    print(f"Average CER (Character Error Rate): {avg_cer:.3f} {cer_quality}")
    print(f"Average WER (Word Error Rate): {avg_wer:.3f}")
    
    # Show best and worst
    best = min(successful, key=lambda r: r.cer)
    worst = max(successful, key=lambda r: r.cer)
    print(f"  Best:  {best.image_path.split('/')[-1]} (CER: {best.cer:.3f})")
    print(f"  Worst: {worst.image_path.split('/')[-1]} (CER: {worst.cer:.3f})")


def main():
    parser = argparse.ArgumentParser(description="Validate OCR quality against ground truth")
    parser.add_argument("--corpus", choices=["Corpus-Correctum", "all"], default="Corpus-Correctum")
    parser.add_argument("--limit", type=int, default=50, help="Max lines to validate per corpus")
    parser.add_argument("--json-output", type=Path, help="Output JSON report")
    
    args = parser.parse_args()
    
    print("\n🔬 OCR Quality Validation (Against Ground Truth)")
    print("=" * 70)
    
    corpus_dir = ROOT / "tests" / "corpus_test" / args.corpus / "data" / "ocr" / "line" / "ambrose" / "32-1"
    
    if not corpus_dir.exists():
        print(f"❌ Corpus directory not found: {corpus_dir}")
        return
    
    results = validate_corpus(corpus_dir, args.corpus, args.limit)
    print_summary(results, args.corpus)
    
    # Save JSON report if requested
    if args.json_output:
        report = {
            "dataset": args.corpus,
            "total_lines": len(results),
            "successful": sum(1 for r in results if r.success),
            "average_cer": sum(r.cer for r in results if r.success) / max(sum(1 for r in results if r.success), 1),
            "average_wer": sum(r.wer for r in results if r.success) / max(sum(1 for r in results if r.success), 1),
            "results": [asdict(r) for r in results]
        }
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(json.dumps(report, indent=2))
        print(f"\n📄 Report saved: {args.json_output}")


if __name__ == "__main__":
    main()
