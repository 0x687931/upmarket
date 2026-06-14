#!/usr/bin/env python3
"""
Validate workflow quality against ground truth using Upmarket CLI.

Measures OCR accuracy, handwriting detection, and metadata extraction
by running documents through the full Upmarket conversion pipeline.
"""

import argparse
import json
import subprocess
import sys
import time
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Optional

ROOT = Path(__file__).parent.parent


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
    """Calculate Character Error Rate (0.0 = perfect, 1.0 = completely wrong)."""
    if len(ground_truth) == 0:
        return 0.0 if len(extracted) == 0 else 1.0
    distance = edit_distance(extracted, ground_truth)
    return min(1.0, distance / len(ground_truth))


def calculate_wer(extracted: str, ground_truth: str) -> float:
    """Calculate Word Error Rate."""
    extracted_words = extracted.split()
    gt_words = ground_truth.split()

    if len(gt_words) == 0:
        return 0.0 if len(extracted_words) == 0 else 1.0

    distance = edit_distance(extracted_words, gt_words)
    return min(1.0, distance / len(gt_words))


@dataclass
class OcrQualityValidation:
    """OCR quality validation result."""
    doc_id: str
    image_path: str
    ground_truth_path: str

    # Ground truth
    ground_truth_text: str = ""

    # Extraction results
    extracted_text: str = ""
    conversion_time_seconds: float = 0.0

    # Accuracy metrics
    cer: float = 0.0  # Character Error Rate
    wer: float = 0.0  # Word Error Rate

    # Workflow features detected
    metadata_extracted: bool = False
    extraction_method: Optional[str] = None
    language_detected: Optional[str] = None
    handwriting_detected: bool = False

    # Status
    success: bool = False
    error_message: Optional[str] = None


def get_cli_binary() -> Path:
    """Get the upmarket-cli binary path."""
    debug_cli = ROOT / "build" / "DerivedData" / "Build" / "Products" / "Debug" / "upmarket-cli"
    if debug_cli.exists():
        return debug_cli

    import shutil
    cli_in_path = shutil.which("upmarket-cli")
    if cli_in_path:
        return Path(cli_in_path)

    raise FileNotFoundError("upmarket-cli not found in build output or PATH")


def get_mcp_directories() -> tuple[Path, Path]:
    """Get MCP input/output directories."""
    app_support = Path.home() / "Library" / "Application Support" / "Upmarket" / "AppGroupFallback"
    mcp_input = app_support / "MCP" / "Inputs"
    mcp_output = app_support / "MCP" / "Outputs"
    mcp_input.mkdir(parents=True, exist_ok=True)
    mcp_output.mkdir(parents=True, exist_ok=True)
    return mcp_input, mcp_output


def validate_line_image(image_path: Path, gt_path: Path) -> OcrQualityValidation:
    """Validate OCR quality on a line image using Upmarket CLI."""
    result = OcrQualityValidation(
        doc_id=image_path.stem,
        image_path=str(image_path),
        ground_truth_path=str(gt_path),
        ground_truth_text=gt_path.read_text(encoding='utf-8', errors='ignore').strip()
    )

    try:
        cli_binary = get_cli_binary()
        mcp_input, mcp_output = get_mcp_directories()

        # Copy image to MCP input directory
        mcp_input_path = mcp_input / image_path.name
        mcp_output_path = mcp_output / f"{image_path.stem}_output.md"

        import shutil
        shutil.copy2(str(image_path), str(mcp_input_path))

        # Run CLI
        start = time.time()
        cmd = [
            str(cli_binary), "convert",
            str(mcp_input_path),
            "-o", str(mcp_output_path),
            "--format", "markdown",
            "--force"
        ]

        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
        result.conversion_time_seconds = time.time() - start

        if proc.returncode != 0:
            result.error_message = f"CLI failed: {proc.stderr[:100]}"
            return result

        if not mcp_output_path.exists():
            result.error_message = "No output generated"
            return result

        # Extract text from markdown output
        markdown = mcp_output_path.read_text(encoding='utf-8', errors='ignore').strip()
        result.extracted_text = markdown

        # Calculate accuracy
        result.cer = calculate_cer(markdown, result.ground_truth_text)
        result.wer = calculate_wer(markdown, result.ground_truth_text)

        result.success = True

        # Cleanup
        try:
            mcp_input_path.unlink()
            mcp_output_path.unlink()
        except:
            pass

    except Exception as e:
        result.error_message = str(e)

    return result


def main():
    parser = argparse.ArgumentParser(
        description="Validate OCR quality against ground truth using Upmarket CLI"
    )
    parser.add_argument(
        "--corpus",
        default="Corpus-Correctum",
        help="Corpus directory name"
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=50,
        help="Max images to validate"
    )
    parser.add_argument(
        "--json-output",
        type=Path,
        help="Save JSON report"
    )

    args = parser.parse_args()

    print("\n🔬 OCR Quality Validation Against Ground Truth")
    print("Using Upmarket CLI (Full Conversion Pipeline)")
    print("=" * 70)

    # Find line images and ground truth
    corpus_dir = ROOT / "tests" / "corpus_test" / args.corpus / "data" / "ocr" / "line" / "ambrose" / "32-1"

    if not corpus_dir.exists():
        print(f"❌ Corpus directory not found: {corpus_dir}")
        sys.exit(1)

    # Get line images
    line_images = sorted(corpus_dir.glob("*.png"))[:args.limit]

    if not line_images:
        print(f"❌ No line images found")
        sys.exit(1)

    print(f"Testing {len(line_images)} line images with ground truth\n")

    results = []
    for i, img_path in enumerate(line_images, 1):
        gt_path = img_path.with_suffix('.gt.txt')
        if not gt_path.exists():
            print(f"[{i}/{len(line_images)}] {img_path.name}... ⚠️  No GT")
            continue

        print(f"[{i}/{len(line_images)}] {img_path.name}...", end=" ", flush=True)
        result = validate_line_image(img_path, gt_path)
        results.append(result)

        if result.success:
            print(f"✓ CER: {result.cer:.3f} WER: {result.wer:.3f}")
        else:
            print(f"✗ {result.error_message[:40]}")

    # Print summary
    print("\n" + "=" * 70)
    successful = [r for r in results if r.success]

    if successful:
        avg_cer = sum(r.cer for r in successful) / len(successful)
        avg_wer = sum(r.wer for r in successful) / len(successful)

        print(f"\n📊 Validation Results ({len(successful)}/{len(results)} successful)")
        print(f"  Average CER (Character Error Rate): {avg_cer:.3f}")
        print(f"  Average WER (Word Error Rate): {avg_wer:.3f}")

        # Quality interpretation
        if avg_cer < 0.01:
            print(f"  Quality: 🟢 Excellent (< 1% error)")
        elif avg_cer < 0.05:
            print(f"  Quality: 🟡 Good (1-5% error)")
        elif avg_cer < 0.10:
            print(f"  Quality: 🟠 Fair (5-10% error)")
        else:
            print(f"  Quality: 🔴 Poor (> 10% error)")

        # Show examples
        best = min(successful, key=lambda r: r.cer)
        worst = max(successful, key=lambda r: r.cer)

        print(f"\n  Best:  {best.doc_id} (CER: {best.cer:.3f})")
        print(f"  Worst: {worst.doc_id} (CER: {worst.cer:.3f})")

    # Save JSON
    if args.json_output:
        report = {
            "corpus": args.corpus,
            "total_validated": len(results),
            "successful": len(successful),
            "average_cer": sum(r.cer for r in successful) / max(len(successful), 1),
            "average_wer": sum(r.wer for r in successful) / max(len(successful), 1),
            "results": [asdict(r) for r in results]
        }
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(json.dumps(report, indent=2))
        print(f"\n📄 Report: {args.json_output}")


if __name__ == "__main__":
    main()
