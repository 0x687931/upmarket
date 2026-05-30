"""
Upmarket document converter — tiered pipeline.

Tier 1 (zero download): PyMuPDF4LLM — fast, bundled, good for clean docs
Tier 2 (172MB download): Enhanced pipeline — layout analysis for complex PDFs
Tier 3 (500MB download): Upmarket AI — Pro, scanned/research documents

No internal library names are exposed to callers.
"""

import os
import sys
import traceback
from pathlib import Path


def convert(file_path: str, options: dict | None = None) -> dict:
    """
    Convert a document to Markdown using the best available pipeline.

    Options:
        use_enhanced (bool): Use enhanced pipeline if downloaded. Default True.
        use_ai (bool): Use Upmarket AI (Pro). Default False.
        ocr (bool): Enable OCR. Default True.
        password (str): PDF password. Default None.

    Returns:
        {
            "success": bool,
            "markdown": str,
            "metadata": { "pages": int, "format": str, "title": str },
            "pipeline": str,  # "fast" | "enhanced" | "ai"
            "error": str | None,
            "needs_password": bool
        }
    """
    opts = options or {}
    path = Path(file_path)

    if not path.exists():
        return _error("Upmarket couldn't find this file. Please try again.")

    suffix = path.suffix.lower()
    password = opts.get("password", None)
    use_enhanced = opts.get("use_enhanced", True)
    use_ai = opts.get("use_ai", False)

    # Check for password-protected PDF first
    if suffix == ".pdf" and not password:
        locked, err = _check_pdf_locked(str(path))
        if locked:
            return {**_error("This PDF is password-protected."), "needs_password": True}
        if err:
            return _error(err)

    # Route to appropriate pipeline
    try:
        if use_ai and _ai_available():
            return _convert_ai(path, opts)

        if suffix == ".pdf" and use_enhanced and _enhanced_available():
            return _convert_enhanced(path, opts)

        if suffix == ".pdf":
            return _convert_fast(path, opts)

        # Non-PDF formats: use enhanced if available, fast otherwise
        if use_enhanced and _enhanced_available():
            return _convert_enhanced(path, opts)

        return _convert_fast(path, opts)

    except Exception as e:
        print(f"[Upmarket] Conversion error: {type(e).__name__}: {e}", file=sys.stderr)
        return _error("Upmarket couldn't convert this document. The file may be damaged, password-protected, or in an unsupported format.")


def check_pipelines() -> dict:
    """
    Returns which pipelines are available.
    { "fast": bool, "enhanced": bool, "ai": bool }
    """
    return {
        "fast": True,  # always available — bundled
        "enhanced": _enhanced_available(),
        "ai": _ai_available(),
    }


# MARK: - Pipeline implementations

def _convert_fast(path: Path, opts: dict) -> dict:
    """
    Fast path — all MIT/BSD/Apache licensed, zero download.
    PDFs: pdfplumber (MIT)
    Everything else: markitdown (MIT, Microsoft)
    """
    suffix = path.suffix.lower()
    password = opts.get("password", None)

    if suffix == ".pdf":
        return _convert_fast_pdf(path, password)
    else:
        return _convert_fast_other(path)


def _convert_fast_pdf(path: Path, password: str | None) -> dict:
    """pdfplumber for PDFs — MIT, handles tables and text well."""
    import pdfplumber

    try:
        open_kwargs = {"password": password} if password else {}
        with pdfplumber.open(str(path), **open_kwargs) as pdf:
            page_count = len(pdf.pages)
            parts = []
            for page in pdf.pages:
                # Tables first
                for table in page.extract_tables():
                    if table:
                        rows = []
                        for i, row in enumerate(table):
                            cells = [str(c or "").strip() for c in row]
                            rows.append("| " + " | ".join(cells) + " |")
                            if i == 0:
                                rows.append("| " + " | ".join(["---"] * len(cells)) + " |")
                        parts.append("\n".join(rows))
                # Text
                text = page.extract_text(x_tolerance=2, y_tolerance=2)
                if text and text.strip():
                    parts.append(text.strip())

            markdown = "\n\n".join(parts)

    except Exception as e:
        msg = str(e).lower()
        if "password" in msg or "encrypted" in msg:
            return {**_error("This PDF is password-protected."), "needs_password": True}
        raise

    return _success(markdown, page_count, path, pipeline="fast")


def _convert_fast_other(path: Path) -> dict:
    """markitdown for DOCX, PPTX, XLSX, HTML, images — MIT (Microsoft)."""
    try:
        from markitdown import MarkItDown
        md_converter = MarkItDown()
        result = md_converter.convert(str(path))
        markdown = result.text_content or ""
        return _success(markdown, 0, path, pipeline="fast")
    except Exception as e:
        suffix = path.suffix.upper().lstrip(".")
        print(f"[Upmarket] markitdown error for {suffix}: {e}", file=sys.stderr)
        return _error(f"Upmarket couldn't convert this {suffix} file. Try the Enhanced pipeline for better results.")


def _convert_enhanced(path: Path, opts: dict) -> dict:
    """Enhanced pipeline — handles all formats, complex layouts, tables."""
    from docling.document_converter import DocumentConverter, PdfFormatOption
    from docling.datamodel.base_models import InputFormat
    from docling.datamodel.pipeline_options import PdfPipelineOptions

    pipeline_options = PdfPipelineOptions()
    pipeline_options.do_ocr = opts.get("ocr", True)
    pipeline_options.do_table_structure = True

    format_options = {}
    pdf_opts = PdfFormatOption(pipeline_options=pipeline_options)

    if opts.get("password"):
        try:
            pdf_opts = PdfFormatOption(
                pipeline_options=pipeline_options,
                backend_options={"password": opts["password"]}
            )
        except Exception:
            pass

    format_options[InputFormat.PDF] = pdf_opts
    converter = DocumentConverter(format_options=format_options)
    result = converter.convert(str(path))
    markdown = result.document.export_to_markdown()
    page_count = result.document.num_pages() if callable(result.document.num_pages) else 0

    return _success(markdown, page_count, path, pipeline="enhanced")


def _convert_ai(path: Path, opts: dict) -> dict:
    """Upmarket AI — Pro tier, best results for complex and scanned documents."""
    # Temporarily re-enable hub for model loading if needed
    was_offline = os.environ.get("HF_HUB_OFFLINE", "0")
    os.environ["HF_HUB_OFFLINE"] = "0"

    try:
        result = _convert_enhanced(path, {**opts, "use_vlm": True})
        result["pipeline"] = "ai"
        return result
    finally:
        os.environ["HF_HUB_OFFLINE"] = was_offline


# MARK: - Availability checks

def _enhanced_available() -> bool:
    """Enhanced pipeline available if layout models are downloaded."""
    cache = Path(os.environ.get("HF_HUB_CACHE",
        Path.home() / "Library" / "Application Support" / "Upmarket" / "models"))
    layout_dir = cache / "layout"
    return layout_dir.exists() and any(layout_dir.iterdir())


def _ai_available() -> bool:
    """Upmarket AI available if AI models are downloaded."""
    cache = Path(os.environ.get("HF_HUB_CACHE",
        Path.home() / "Library" / "Application Support" / "Upmarket" / "models"))
    ai_dir = cache / "upmarket_ai"
    return ai_dir.exists() and any(ai_dir.iterdir())


# MARK: - Helpers

def _check_pdf_locked(file_path: str) -> tuple[bool, str | None]:
    try:
        import pypdfium2 as pdfium
        doc = pdfium.PdfDocument(file_path)
        doc.close()
        return False, None
    except Exception as e:
        msg = str(e).lower()
        if "password" in msg or "encrypted" in msg:
            return True, None
        return False, None


def _count_pdf_pages(file_path: str, password: str | None = None) -> int:
    try:
        import pdfplumber
        kwargs = {"password": password} if password else {}
        with pdfplumber.open(file_path, **kwargs) as pdf:
            return len(pdf.pages)
    except Exception:
        return 0


def _success(markdown: str, pages: int, path: Path, pipeline: str) -> dict:
    return {
        "success": True,
        "markdown": markdown,
        "metadata": {
            "pages": pages,
            "format": path.suffix.lstrip(".").upper(),
            "title": path.stem,
        },
        "pipeline": pipeline,
        "error": None,
        "needs_password": False,
    }


def _error(message: str) -> dict:
    return {
        "success": False,
        "markdown": "",
        "metadata": {},
        "pipeline": "none",
        "error": message,
        "needs_password": False,
    }
