"""
Fast document complexity analyser.
Runs a lightweight structural scan before full conversion to determine
whether Upmarket AI would give significantly better results.

Never exposes internal library names to callers.
"""

import traceback
from pathlib import Path


# Complexity score thresholds
SCORE_SIMPLE   = 30   # Basic pipeline is fine
SCORE_MODERATE = 60   # AI recommended but not critical
SCORE_COMPLEX  = 100  # AI strongly recommended


def analyse(file_path: str) -> dict:
    """
    Quickly analyse a document's complexity without full conversion.

    Returns:
    {
        "success": bool,
        "score": int,                  # 0-100+ complexity score
        "recommendation": str,         # "basic" | "ai_recommended" | "ai_required"
        "reasons": [str],              # User-friendly reasons why AI helps
        "signals": {                   # Raw signals for debugging
            "is_scanned": bool,
            "page_count": int,
            "has_complex_tables": bool,
            "has_figures": bool,
            "text_coverage": float,    # 0.0-1.0, low = scanned/image heavy
        },
        "error": str | None
    }
    """
    try:
        path = Path(file_path)
        if not path.exists():
            return _error("File not found.")

        suffix = path.suffix.lower()

        # Non-PDF formats are generally clean digital — Basic is fine
        if suffix in (".docx", ".pptx", ".xlsx", ".html", ".htm"):
            return _simple(suffix)

        # For PDFs, do a lightweight structural scan
        if suffix == ".pdf":
            return _analyse_pdf(path)

        # Images always benefit from AI
        if suffix in (".png", ".jpg", ".jpeg", ".tiff", ".bmp"):
            return _result(
                score=80,
                recommendation="ai_recommended",
                reasons=["Images often contain text that Upmarket AI reads more accurately"],
                signals={"is_scanned": True, "page_count": 1, "has_complex_tables": False,
                         "has_figures": True, "text_coverage": 0.0}
            )

        return _simple(suffix)

    except Exception as e:
        import sys
        print(f"[Upmarket] Analysis error: {e}", file=sys.stderr)
        # On analysis failure, default to basic — don't block conversion
        return _result(score=0, recommendation="basic", reasons=[], signals={})


def _analyse_pdf(path: Path) -> dict:
    from docling.document_converter import DocumentConverter, PdfFormatOption
    from docling.datamodel.base_models import InputFormat
    from docling.datamodel.pipeline_options import PdfPipelineOptions

    # Lightweight parse — no OCR, no table structure, just layout
    pipeline_options = PdfPipelineOptions()
    pipeline_options.do_ocr = False
    pipeline_options.do_table_structure = False

    converter = DocumentConverter(
        format_options={
            InputFormat.PDF: PdfFormatOption(pipeline_options=pipeline_options)
        }
    )

    result = converter.convert(str(path))
    doc = result.document

    page_count = doc.num_pages() if callable(doc.num_pages) else 0
    texts = list(doc.texts) if hasattr(doc, "texts") else []
    tables = list(doc.tables) if hasattr(doc, "tables") else []
    pictures = list(doc.pictures) if hasattr(doc, "pictures") else []

    # Calculate text coverage — low coverage means scanned/image-heavy
    total_chars = sum(len(t.text) for t in texts if hasattr(t, "text") and t.text)
    expected_chars = page_count * 500  # rough expected chars per page
    text_coverage = min(1.0, total_chars / expected_chars) if expected_chars > 0 else 0.0

    is_scanned = text_coverage < 0.2
    has_complex_tables = len(tables) > 3
    has_figures = len(pictures) > 2
    is_multicolumn = _detect_multicolumn(texts, page_count)

    # Score signals
    score = 0
    reasons = []

    if is_scanned:
        score += 50
        reasons.append("Contains scanned or image-based pages")

    if has_complex_tables:
        score += 25
        reasons.append("Contains multiple complex tables")

    if has_figures:
        score += 15
        reasons.append("Contains figures and diagrams")

    if is_multicolumn:
        score += 20
        reasons.append("Multi-column or complex layout")

    if page_count > 50:
        score += 10

    # Determine recommendation
    if score >= SCORE_COMPLEX:
        recommendation = "ai_required"
    elif score >= SCORE_MODERATE:
        recommendation = "ai_recommended"
    else:
        recommendation = "basic"

    return _result(
        score=score,
        recommendation=recommendation,
        reasons=reasons,
        signals={
            "is_scanned": is_scanned,
            "page_count": page_count,
            "has_complex_tables": has_complex_tables,
            "has_figures": has_figures,
            "text_coverage": round(text_coverage, 2),
        }
    )


def _detect_multicolumn(texts, page_count: int) -> bool:
    """Rough heuristic: if many text blocks have x-positions in two distinct clusters."""
    if not texts or page_count == 0:
        return False
    try:
        xs = []
        for t in texts[:50]:  # sample first 50 blocks
            if hasattr(t, "prov") and t.prov:
                bbox = t.prov[0].bbox if hasattr(t.prov[0], "bbox") else None
                if bbox and hasattr(bbox, "l"):
                    xs.append(bbox.l)
        if len(xs) < 10:
            return False
        # Simple bimodal check: std dev suggests spread across columns
        mean = sum(xs) / len(xs)
        variance = sum((x - mean) ** 2 for x in xs) / len(xs)
        return variance > 10000  # high variance = likely multi-column
    except Exception:
        return False


def _simple(suffix: str) -> dict:
    return _result(
        score=10,
        recommendation="basic",
        reasons=[],
        signals={"is_scanned": False, "page_count": 0,
                 "has_complex_tables": False, "has_figures": False,
                 "text_coverage": 1.0}
    )


def _result(score: int, recommendation: str, reasons: list, signals: dict) -> dict:
    return {
        "success": True,
        "score": score,
        "recommendation": recommendation,
        "reasons": reasons,
        "signals": signals,
        "error": None,
    }


def _error(message: str) -> dict:
    return {
        "success": False,
        "score": 0,
        "recommendation": "basic",
        "reasons": [],
        "signals": {},
        "error": message,
    }
