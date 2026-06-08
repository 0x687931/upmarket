"""
benchmark_quality.py — Multi-pathway quality benchmark.

Mirrors ConversionRunner's quality-selection logic exactly:
- PDF/image documents only (DOCX/PPTX/etc. use MarkItDown, single pathway)
- Entitlement tiers: basic (PDFKit + Vision), pro_ai (+ Enhanced + AI)
- Runs all applicable pathways concurrently (mirrors async let in Swift)
- Scores each result with a Python port of MarkdownQualityScorer.swift
- Picks winner with same best() logic: highest overall, tie-break on length
- Reports per-document table with all pathway scores and winner

Usage:
    python3 scripts/benchmark_quality.py
    python3 scripts/benchmark_quality.py --tier basic
    python3 scripts/benchmark_quality.py --tier pro_ai
    python3 scripts/benchmark_quality.py --bucket scanned-or-unknown
    python3 scripts/benchmark_quality.py --doc docling_test_01
    python3 scripts/benchmark_quality.py --json-output reports/quality-comparison.json
"""

import argparse
import json
import os
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field, asdict
from pathlib import Path

ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT / "UpmarketPython"))

CORPUS_DIR = ROOT / "tests" / "corpus"
VENV_PYTHON = ROOT / ".venv" / "bin" / "python3"

PDF_IMAGE_FORMATS = {"pdf", "png", "jpg", "jpeg", "tif", "tiff", "webp"}

PATHWAYS = {
    "basic": ["pdfkit", "vision"],
    "pro_ai": ["pdfkit", "vision", "enhanced", "ai"],
}


# ── Quality scorer (port of MarkdownQualityScorer.swift) ──────────────────────

@dataclass
class QualityScore:
    overall: float = 0.0
    language_confidence: float = 0.0
    coverage: float = 0.0
    structure: float = 0.0
    artifact_penalty: float = 0.0
    duplication_penalty: float = 0.0
    image_text_agreement: float | None = None
    reasons: list[str] = field(default_factory=list)


def _language_confidence(text: str) -> float:
    """Port of NLLanguageRecognizer. Falls back to langdetect if available."""
    sample = text[:8000]
    try:
        from langdetect import detect_langs
        langs = detect_langs(sample)
        return max(0.0, min(1.0, langs[0].prob)) if langs else 0.35
    except Exception:
        # Heuristic: if text has mostly ASCII letters it's likely English
        alpha = sum(1 for c in sample if c.isalpha())
        ascii_alpha = sum(1 for c in sample if c.isascii() and c.isalpha())
        return 0.75 if alpha > 0 and ascii_alpha / max(alpha, 1) > 0.85 else 0.35


def _coverage_score(markdown: str, pages: int) -> float:
    word_count = len(markdown.split())
    page_count = max(pages, 1)
    words_per_page = word_count / page_count
    score = min(1.0, words_per_page / 180.0)
    if pages > 1 and "\n\n---\n\n" in markdown:
        score = min(1.0, score + 0.08)
    return max(0.0, min(1.0, score))


def _structure_score(markdown: str) -> float:
    lines = markdown.splitlines()
    heading_count = sum(1 for l in lines if l.strip().startswith("#"))
    list_count = sum(
        1 for l in lines
        if l.strip().startswith("- ") or re.match(r"^\d+\.\s", l.strip())
    )
    table_count = sum(1 for l in lines if re.match(r"^\|[\s\-|:]+\|$", l.strip()))
    score = 0.45
    if heading_count > 0: score += 0.18
    if list_count > 0:    score += 0.10
    if table_count > 0:   score += 0.22
    if "```" in markdown:  score += 0.08
    return max(0.0, min(1.0, score))


def _artifact_penalty(markdown: str) -> float:
    count = 0
    count += markdown.count("�")
    count += markdown.count("­")
    count += len(re.findall(r"\n\d{1,3}\n", markdown))
    count += len(re.findall(r"[A-Za-z]-\s+[a-z]", markdown))
    count += len(re.findall(r"(.)\1{8,}", markdown))
    return min(1.0, count / 12.0)


def _duplication_penalty(markdown: str) -> float:
    lines = [l.strip() for l in markdown.splitlines() if len(l.strip()) > 8]
    if len(lines) <= 4:
        return 0.0
    from collections import Counter
    counts = Counter(lines)
    repeated = sum(v for v in counts.values() if v > 1)
    return min(1.0, repeated / len(lines))


def _token_set(text: str) -> set:
    return {t for t in re.split(r"[^a-z0-9]+", text.lower()) if len(t) > 2}


def _text_agreement(candidate: str, reference: str) -> float:
    cand_tokens = _token_set(candidate)
    ref_tokens = _token_set(reference)
    if not cand_tokens or not ref_tokens:
        return 0.0
    overlap = len(cand_tokens & ref_tokens)
    return overlap / len(ref_tokens)


def quality_score(markdown: str, pages: int = 1, image_text: str | None = None) -> QualityScore:
    """Exact port of MarkdownQualityScorer.score() from Swift."""
    normalized = markdown.strip()
    if not normalized:
        return QualityScore(
            overall=0, language_confidence=0, coverage=0, structure=0,
            artifact_penalty=1, duplication_penalty=1,
            image_text_agreement=0.0 if image_text is not None else None,
            reasons=["empty output"],
        )

    language   = _language_confidence(normalized)
    coverage   = _coverage_score(normalized, pages)
    structure  = _structure_score(normalized)
    artifact   = _artifact_penalty(normalized)
    duplication = _duplication_penalty(normalized)
    agreement  = _text_agreement(normalized, image_text) if image_text is not None else None

    # Weights mirror MarkdownQualityScorer.swift exactly
    weighted = [
        (language,          0.20),
        (coverage,          0.30),
        (structure,         0.20),
        (1.0 - artifact,    0.15),
        (1.0 - duplication, 0.15),
    ]
    if agreement is not None:
        weighted.append((agreement, 0.18))

    total_weight = sum(w for _, w in weighted)
    overall = sum(v * w for v, w in weighted) / max(total_weight, 0.01)
    overall = max(0.0, min(1.0, overall))

    reasons = []
    if language    < 0.45: reasons.append("low language confidence")
    if coverage    < 0.45: reasons.append("low coverage")
    if structure   < 0.45: reasons.append("low structure")
    if artifact    > 0.25: reasons.append("extraction artifacts")
    if duplication > 0.25: reasons.append("duplicate text")
    if agreement is not None and agreement < 0.35:
        reasons.append("low image-text agreement")

    return QualityScore(
        overall=overall,
        language_confidence=language,
        coverage=coverage,
        structure=structure,
        artifact_penalty=artifact,
        duplication_penalty=duplication,
        image_text_agreement=agreement,
        reasons=reasons,
    )


def best_candidate(candidates: list[dict]) -> dict | None:
    """Port of MarkdownQualityScorer.best(). Tie-break: longer markdown wins."""
    if not candidates:
        return None
    return max(candidates, key=lambda c: (c["score"].overall, len(c["markdown"])))


# ── Pathway converters ────────────────────────────────────────────────────────

def _venv_convert(doc_path: Path, opts: dict) -> tuple[str, float]:
    from docling_bridge.converter import convert
    start = time.time()
    result = convert(str(doc_path), opts)
    elapsed = time.time() - start
    if result.get("success"):
        return result["markdown"], elapsed
    raise RuntimeError(result.get("error", "conversion failed"))


def _swift_pdfkit(doc_path: Path) -> tuple[str, float]:
    """PDFKit via the bundled xcframework Python bridge (fast path)."""
    site = ROOT / "Upmarket/Python/Python.xcframework/macos-arm64_x86_64/Python.framework/Versions/3.12/lib/python3.12/site-packages"
    if str(site) not in sys.path:
        sys.path.insert(0, str(site))
    return _venv_convert(doc_path, {"use_enhanced": False, "use_ai": False})


def _vision_ocr(doc_path: Path) -> tuple[str, float]:
    """Vision OCR via the fast pdfium path (closest proxy in Python benchmark)."""
    return _venv_convert(doc_path, {"use_enhanced": False, "use_ai": False})


def _enhanced(doc_path: Path) -> tuple[str, float]:
    return _venv_convert(doc_path, {"use_enhanced": True, "use_ai": False})


def _ai(doc_path: Path) -> tuple[str, float]:
    return _venv_convert(doc_path, {"use_enhanced": True, "use_ai": True})


PATHWAY_FN = {
    "pdfkit":   (_swift_pdfkit, 30),
    "vision":   (_vision_ocr,   30),
    "enhanced": (_enhanced,    120),
    "ai":       (_ai,          300),
}

PATHWAY_LABEL = {
    "pdfkit":   "PDFKit",
    "vision":   "Vision OCR",
    "enhanced": "Enhanced",
    "ai":       "AI (Granite)",
}


# ── Runner ────────────────────────────────────────────────────────────────────

def run_pathway(pathway: str, doc_path: Path) -> dict:
    """Run a single pathway. Timeout enforced via future.result(timeout=) in caller."""
    fn, _ = PATHWAY_FN[pathway]
    start = time.time()
    try:
        markdown, elapsed = fn(doc_path)
        return {"pathway": pathway, "ok": True, "markdown": markdown, "elapsed": elapsed}
    except Exception as e:
        return {"pathway": pathway, "ok": False, "markdown": "", "elapsed": time.time() - start, "error": str(e)[:200]}


def run_document(doc_meta: dict, corpus_dir: Path, tier: str) -> dict:
    doc_id = doc_meta["id"]
    fmt = doc_meta.get("format", "").lower()
    if fmt not in PDF_IMAGE_FORMATS:
        return {"id": doc_id, "skipped": True, "reason": f"format={fmt} not PDF/image"}

    file_path = corpus_dir / doc_meta["file"]
    if not file_path.exists():
        file_path = corpus_dir / "docling" / "docling" / doc_meta["file"]
    if not file_path.exists():
        return {"id": doc_id, "skipped": True, "reason": "file not found"}

    pathways = PATHWAYS[tier]

    # GPU scheduling — avoid concurrent Metal/MPS use:
    #
    #   pdfkit    — CPU + CoreGraphics          safe to parallelise freely
    #   vision    — Apple Neural Engine (ANE)   safe alongside CPU and MLX
    #   enhanced  — PyTorch MPS (GPU)           must finish before AI starts
    #   ai        — MLX Metal (GPU)             main-thread only; after enhanced
    #
    # Phase 1: pdfkit + vision + enhanced run concurrently.
    #          PDFKit and Vision use CPU/ANE; Enhanced uses MPS but MLX has
    #          not yet initialised its Metal stream, so there is no conflict.
    # Phase 2: pool joins (enhanced done); AI runs on main thread with sole
    #          Metal access. Vision's ANE work continues safely in parallel.
    #
    # This mirrors the app: Swift runs PDFKit/Vision via async let on the
    # cooperative pool while Python/AI runs in a separate helper process.

    phase1 = [p for p in pathways if p != "ai"]
    run_ai = "ai" in pathways
    results = {}

    # Phase 1 — CPU/ANE/MPS pathways concurrently
    with ThreadPoolExecutor(max_workers=max(len(phase1), 1)) as pool:
        futures = {pool.submit(run_pathway, p, file_path): p for p in phase1}
        for future in as_completed(futures):
            p = futures[future]
            _, timeout = PATHWAY_FN[p]
            try:
                r = future.result(timeout=timeout)
            except TimeoutError:
                r = {"pathway": p, "ok": False, "markdown": "", "elapsed": timeout,
                     "error": f"timed out after {timeout}s"}
            results[p] = r

    # Phase 2 — AI on main thread; Enhanced MPS work is now complete
    if run_ai:
        results["ai"] = run_pathway("ai", file_path)

    # Score each successful result
    vision_md = results.get("vision", {}).get("markdown") if results.get("vision", {}).get("ok") else None
    candidates = []
    for pathway in pathways:
        r = results[pathway]
        if not r["ok"]:
            continue
        score = quality_score(r["markdown"], pages=1, image_text=vision_md if pathway != "vision" else None)
        candidates.append({
            "pathway": pathway,
            "label": PATHWAY_LABEL[pathway],
            "markdown": r["markdown"],
            "elapsed": r["elapsed"],
            "score": score,
        })

    winner = best_candidate(candidates)

    return {
        "id": doc_id,
        "skipped": False,
        "format": fmt,
        "bucket": doc_meta.get("bucket"),
        "candidates": [
            {
                "pathway": c["pathway"],
                "label": c["label"],
                "elapsed": round(c["elapsed"], 3),
                "overall": round(c["score"].overall, 3),
                "language_confidence": round(c["score"].language_confidence, 3),
                "coverage": round(c["score"].coverage, 3),
                "structure": round(c["score"].structure, 3),
                "artifact_penalty": round(c["score"].artifact_penalty, 3),
                "duplication_penalty": round(c["score"].duplication_penalty, 3),
                "reasons": c["score"].reasons,
                "winner": c["pathway"] == (winner["pathway"] if winner else None),
            }
            for c in candidates
        ],
        "errors": {p: results[p]["error"] for p in pathways if not results[p].get("ok")},
        "winner": winner["pathway"] if winner else None,
        "winner_score": round(winner["score"].overall, 3) if winner else 0,
    }


def print_document_result(r: dict) -> None:
    if r.get("skipped"):
        return
    doc_id = r["id"]
    winner = r.get("winner")
    winner_score = r.get("winner_score", 0)
    flag = "✓" if winner_score >= 0.8 else "⚠" if winner_score >= 0.6 else "✗"
    print(f"\n  {flag} {doc_id}")
    for c in r.get("candidates", []):
        w = "◀ winner" if c["winner"] else ""
        reasons = f"  [{', '.join(c['reasons'])}]" if c["reasons"] else ""
        print(
            f"    {c['label']:14}  {c['overall']*100:5.1f}%"
            f"  lang={c['language_confidence']:.2f}"
            f"  cov={c['coverage']:.2f}"
            f"  str={c['structure']:.2f}"
            f"  art={c['artifact_penalty']:.2f}"
            f"  dup={c['duplication_penalty']:.2f}"
            f"  {c['elapsed']:.1f}s"
            f"  {w}{reasons}"
        )
    for p, err in r.get("errors", {}).items():
        print(f"    {PATHWAY_LABEL.get(p, p):14}  ERROR: {err[:80]}")


def print_summary(results: list[dict], tier: str) -> None:
    scored = [r for r in results if not r.get("skipped") and r.get("candidates")]
    if not scored:
        print("\nNo scored documents.")
        return

    pathways = PATHWAYS[tier]
    wins = {p: 0 for p in pathways}
    totals = {p: [] for p in pathways}

    for r in scored:
        if r.get("winner"):
            wins[r["winner"]] = wins.get(r["winner"], 0) + 1
        for c in r.get("candidates", []):
            totals[c["pathway"]].append(c["overall"])

    print(f"\n{'═'*65}")
    print(f"  Summary — tier: {tier}  ({len(scored)} PDF/image documents)")
    print(f"{'─'*65}")
    print(f"  {'Pathway':14}  {'Avg Quality':>11}  {'Wins':>5}  {'Win %':>6}")
    print(f"{'─'*65}")
    for p in pathways:
        scores = totals.get(p, [])
        avg = sum(scores) / len(scores) if scores else 0
        w = wins.get(p, 0)
        pct = w / len(scored) * 100 if scored else 0
        print(f"  {PATHWAY_LABEL.get(p,p):14}  {avg*100:>10.1f}%  {w:>5}  {pct:>5.1f}%")
    print(f"{'═'*65}")


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tier", choices=["basic", "pro_ai"], default="pro_ai")
    parser.add_argument("--bucket", help="Filter by corpus bucket (e.g. scanned-or-unknown)")
    parser.add_argument("--doc", help="Run a single document by ID")
    parser.add_argument("--json-output", help="Write full results JSON to this path")
    parser.add_argument("--corpus", default=str(CORPUS_DIR))
    args = parser.parse_args()

    corpus_dir = Path(args.corpus)
    manifest = json.loads((corpus_dir / "manifest.json").read_text())
    docs = manifest["documents"]

    # Overlay bucket labels from the classifier report — same source as benchmark_scorer.py.
    # The manifest stores bucket=null; the classification report has the per-doc assignments.
    bucket_label_path = ROOT / "docs/release/corpus_bucket_classification.json"
    if bucket_label_path.exists():
        try:
            bucket_data = json.loads(bucket_label_path.read_text())
            bucket_labels = {
                d["id"]: d["bucket"]
                for d in bucket_data.get("documents", [])
                if d.get("id") and d.get("bucket")
            }
            for d in docs:
                if d["id"] in bucket_labels:
                    d["bucket"] = bucket_labels[d["id"]]
        except Exception:
            pass

    if args.doc:
        docs = [d for d in docs if d["id"] == args.doc]
    if args.bucket:
        docs = [d for d in docs if d.get("bucket") == args.bucket]

    # Set up environment to match production
    corpus_abs = str(corpus_dir.resolve())
    os.environ["UPMARKET_ALLOWED_INPUT_ROOTS"] = corpus_abs
    os.environ.setdefault("UPMARKET_MODELS_DIR", str(Path.home() / "Library/Application Support/Upmarket/models"))
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"

    print(f"{'═'*65}")
    print(f"  Upmarket Quality Benchmark")
    print(f"  Tier: {args.tier}  Pathways: {', '.join(PATHWAY_LABEL[p] for p in PATHWAYS[args.tier])}")
    print(f"  Corpus: {corpus_dir}")
    if args.bucket: print(f"  Bucket: {args.bucket}")
    print(f"{'═'*65}")

    # Filter to PDF/image only — DOCX/PPTX etc. are single-pathway
    pdf_image_docs = [d for d in docs if d.get("format", "").lower() in PDF_IMAGE_FORMATS]
    other_docs = [d for d in docs if d.get("format", "").lower() not in PDF_IMAGE_FORMATS]
    if other_docs:
        print(f"\n  Skipping {len(other_docs)} non-PDF/image documents (single-pathway formats)")

    print(f"\n  Running {len(pdf_image_docs)} PDF/image documents\n")

    all_results = []
    for doc_meta in pdf_image_docs:
        r = run_document(doc_meta, corpus_dir, args.tier)
        print_document_result(r)
        all_results.append(r)

    print_summary(all_results, args.tier)

    if args.json_output:
        out = Path(args.json_output)
        out.parent.mkdir(parents=True, exist_ok=True)
        # Make results JSON-serialisable (remove score objects)
        out.write_text(json.dumps(all_results, indent=2, default=str))
        print(f"\n  JSON report: {out}")


if __name__ == "__main__":
    main()
