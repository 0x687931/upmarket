"""
Upmarket benchmark scorer.
Converts corpus documents and scores against ground truth (.expected.md).
"""

import argparse
import json
import re
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path


# ── Scoring ───────────────────────────────────────────────────────────────────

@dataclass
class DocScore:
    doc_id: str
    category: str
    heading_recall: float = 0.0
    table_accuracy: float = 0.0
    content_completeness: float = 0.0
    markdown_valid: bool = True
    artifacts_found: int = 0
    elapsed_seconds: float = 0.0
    error: str | None = None

    @property
    def overall(self) -> float:
        if self.error:
            return 0.0
        w = [
            (self.heading_recall,       0.30),
            (self.table_accuracy,       0.25),
            (self.content_completeness, 0.30),
            (1.0 if self.markdown_valid else 0.0, 0.10),
            (max(0.0, 1.0 - self.artifacts_found / 10), 0.05),
        ]
        return sum(score * weight for score, weight in w)


def score_document(output_md: str, meta: dict) -> DocScore:
    doc_id = meta.get("id", "unknown")
    category = meta.get("category", "unknown")
    score = DocScore(doc_id=doc_id, category=category)

    features = meta.get("expected_features", {})

    # Heading recall
    expected_headings = features.get("headings", [])
    if expected_headings:
        found = extract_headings(output_md)
        matched = sum(
            1 for h in expected_headings
            if any(h.lower() in f.lower() for f in found)
        )
        score.heading_recall = matched / len(expected_headings)
    else:
        score.heading_recall = 1.0  # N/A

    # Table accuracy
    expected_tables = features.get("tables", 0)
    found_tables = count_md_tables(output_md)
    if expected_tables == 0:
        score.table_accuracy = 1.0 if found_tables == 0 else 0.8
    else:
        ratio = found_tables / expected_tables
        score.table_accuracy = min(1.0, ratio) if ratio <= 1.5 else max(0.0, 2.0 - ratio)

    # Content completeness (word count ±20%)
    expected_words = features.get("estimated_words", 0)
    if expected_words > 0:
        actual_words = len(output_md.split())
        ratio = actual_words / expected_words
        if 0.8 <= ratio <= 1.2:
            score.content_completeness = 1.0
        elif 0.6 <= ratio <= 1.4:
            score.content_completeness = 0.7
        else:
            score.content_completeness = max(0.0, 1.0 - abs(ratio - 1.0))
    else:
        score.content_completeness = 1.0 if len(output_md) > 100 else 0.0

    # Markdown validity
    score.markdown_valid = validate_markdown(output_md)

    # Artifact detection (PDF noise)
    score.artifacts_found = count_artifacts(output_md)

    return score


def extract_headings(md: str) -> list[str]:
    return [
        re.sub(r'^#+\s*', '', line).strip()
        for line in md.splitlines()
        if line.strip().startswith('#')
    ]


def count_md_tables(md: str) -> int:
    # Count table separator rows (| --- | --- |)
    return len(re.findall(r'^\|[\s\-|:]+\|', md, re.MULTILINE))


def validate_markdown(md: str) -> bool:
    # Check for obviously broken Markdown
    lines = md.splitlines()
    in_table = False
    for line in lines:
        stripped = line.strip()
        # Unclosed bold/italic
        if stripped.count('**') % 2 != 0:
            return False
        # Table row without closing pipe
        if stripped.startswith('|') and not stripped.endswith('|'):
            return False
    return True


def count_artifacts(md: str) -> int:
    """Count PDF extraction artifacts that should have been cleaned."""
    artifacts = 0
    # Page numbers floating in text
    artifacts += len(re.findall(r'\n\d{1,3}\n', md))
    # Soft hyphens
    artifacts += md.count('\xad')
    # Replacement chars
    artifacts += md.count('') + md.count('')
    # Ligature chars not cleaned
    for lig in ['ﬁ', 'ﬂ', 'ﬃ', 'ﬄ', 'ﬀ']:
        artifacts += md.count(lig)
    return artifacts


# ── Conversion ────────────────────────────────────────────────────────────────

def convert_document(doc_path: Path, pipeline: str) -> tuple[str, float]:
    """Convert a document and return (markdown, elapsed_seconds)."""
    import sys
    site = Path(__file__).parent.parent / 'Upmarket/Python/Python.xcframework/macos-arm64_x86_64/Python.framework/Versions/3.12/lib/python3.12/site-packages'
    if str(site) not in sys.path:
        sys.path.insert(0, str(site))

    from docling_bridge.converter import convert

    opts = {
        "use_enhanced": pipeline in ("enhanced", "ai"),
        "use_ai": pipeline == "ai",
    }

    start = time.time()
    result = convert(str(doc_path), opts)
    elapsed = time.time() - start

    if result.get("success"):
        return result["markdown"], elapsed
    else:
        raise RuntimeError(result.get("error", "Unknown error"))


# ── Runner ────────────────────────────────────────────────────────────────────

def run_benchmark(corpus_dir: Path, pipeline: str, category_filter: str, fail_below: int) -> int:
    scores: list[DocScore] = []
    manifest_path = corpus_dir / "manifest.json"

    if not manifest_path.exists():
        print(f"No manifest.json found in {corpus_dir}")
        print("Create corpus first: see docs/CORPUS_STRATEGY.md")
        return 0

    manifest = json.loads(manifest_path.read_text())
    docs = manifest.get("documents", [])

    if category_filter:
        docs = [d for d in docs if d.get("category", "").startswith(category_filter)]

    if not docs:
        print(f"No documents found{' for category: ' + category_filter if category_filter else ''}")
        return 0

    print(f"Running {len(docs)} documents | pipeline: {pipeline or 'auto'}\n")

    for doc_meta in docs:
        doc_id = doc_meta["id"]
        category = doc_meta.get("category", "unknown")
        file_path = corpus_dir / doc_meta["file"]

        if not file_path.exists():
            print(f"  SKIP {doc_id} — file not found")
            continue

        print(f"  {doc_id:<40}", end="", flush=True)

        try:
            markdown, elapsed = convert_document(file_path, pipeline or "fast")
            score = score_document(markdown, doc_meta)
            score.elapsed_seconds = elapsed
            scores.append(score)
            status = "✓" if score.overall >= 0.8 else "⚠" if score.overall >= 0.6 else "✗"
            print(f"{status}  {score.overall*100:.0f}%  ({elapsed:.1f}s)")
        except Exception as e:
            score = DocScore(doc_id=doc_id, category=category, error=str(e))
            scores.append(score)
            print(f"✗  ERROR: {e}")

    # Summary table
    print("\n" + "═" * 65)
    print_summary(scores)

    overall_avg = sum(s.overall for s in scores) / len(scores) if scores else 0
    print(f"\nOverall: {overall_avg*100:.1f}%  ({len(scores)} documents)")

    if fail_below > 0 and overall_avg * 100 < fail_below:
        print(f"\nFAIL: score {overall_avg*100:.1f}% below threshold {fail_below}%")
        return 1

    return 0


def print_summary(scores: list[DocScore]):
    # Group by category
    by_category: dict[str, list[DocScore]] = {}
    for s in scores:
        cat = s.category.split("/")[0]
        by_category.setdefault(cat, []).append(s)

    header = f"{'Category':<25} {'Docs':>4} {'Headings':>8} {'Tables':>7} {'Content':>8} {'Overall':>8}"
    print(header)
    print("-" * 65)

    for cat, cat_scores in sorted(by_category.items()):
        valid = [s for s in cat_scores if not s.error]
        if not valid:
            continue
        avg = lambda f: sum(getattr(s, f) for s in valid) / len(valid)
        print(
            f"{cat:<25} {len(cat_scores):>4} "
            f"{avg('heading_recall')*100:>7.0f}% "
            f"{avg('table_accuracy')*100:>6.0f}% "
            f"{avg('content_completeness')*100:>7.0f}% "
            f"{sum(s.overall for s in valid)/len(valid)*100:>7.0f}%"
        )


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Upmarket benchmark scorer")
    parser.add_argument("--corpus", required=True)
    parser.add_argument("--pipeline", default="")
    parser.add_argument("--category", default="")
    parser.add_argument("--fail-below", type=int, default=0)
    args = parser.parse_args()

    sys.exit(run_benchmark(
        corpus_dir=Path(args.corpus),
        pipeline=args.pipeline,
        category_filter=args.category,
        fail_below=args.fail_below,
    ))
