"""
Upmarket document converter — tiered pipeline.

Tier 1 (zero download): pdfium + post-processor for PDFs, markitdown for everything else
Tier 2 (172MB download): Enhanced pipeline — layout analysis for complex PDFs
Tier 3 (500MB download): Upmarket AI — Pro, scanned/research documents

No internal library names are exposed to callers.
"""

import os
import sys
from pathlib import Path
from docling_bridge.security import validate_file_path, validate_password, log_security_event


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

    # Security: validate path (traversal, size) and password (buffer overrun)
    try:
        file_path = validate_file_path(file_path)
        password_raw = opts.get("password", None)
        password_raw = validate_password(password_raw)
    except ValueError as e:
        log_security_event("INPUT_VALIDATION_FAILED", str(e))
        return _error(f"Upmarket couldn't open this file: {e}")

    path = Path(file_path)
    suffix = path.suffix.lower()
    password = password_raw
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
            return _convert_fast_pdf(path, password)

        # Non-PDF formats: use enhanced if available, fast otherwise
        if use_enhanced and _enhanced_available():
            return _convert_enhanced(path, opts)

        return _convert_fast_other(path)

    except Exception as e:
        print(f"[Upmarket] Conversion error: {type(e).__name__}: {e}", file=sys.stderr)
        return _error("Upmarket couldn't convert this document. The file may be damaged, password-protected, or in an unsupported format.")


def check_pipelines() -> dict:
    """Returns which pipelines are available."""
    return {
        "fast": True,
        "enhanced": _enhanced_available(),
        "ai": _ai_available(),
    }


# MARK: - Pipeline implementations

def _convert_fast_pdf(path: Path, password: str | None) -> dict:
    """
    pdfium (Apache 2.0) + structured post-processing → clean Markdown.
    Uses block-level rect extraction with font-size heuristics for headings,
    paragraph merging, ligature fixing, and running header removal.
    """
    try:
        from docling_bridge.postprocessor import pdf_to_clean_markdown
        markdown, page_count = pdf_to_clean_markdown(str(path), password=password)
        return _success(markdown, page_count, path, pipeline="fast")
    except Exception as e:
        msg = str(e).lower()
        if "password" in msg or "encrypted" in msg:
            return {**_error("This PDF is password-protected."), "needs_password": True}
        print(f"[Upmarket] Post-processor error: {e}", file=sys.stderr)
        return _error("Upmarket couldn't convert this PDF.")


def _convert_fast_other(path: Path) -> dict:
    """markitdown for DOCX, PPTX, XLSX, HTML, images, audio, EPUB — MIT (Microsoft)."""
    try:
        from markitdown import MarkItDown
        md_converter = MarkItDown()
        result = md_converter.convert(str(path))
        markdown = result.text_content or ""
        return _success(markdown, 0, path, pipeline="fast")
    except Exception as e:
        suffix = path.suffix.upper().lstrip(".")
        print(f"[Upmarket] markitdown error for {suffix}: {e}", file=sys.stderr)
        return _error(f"Upmarket couldn't convert this {suffix} file. Try downloading the Enhanced pipeline for better results.")


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
    cache = Path(os.environ.get("HF_HUB_CACHE",
        Path.home() / "Library" / "Application Support" / "Upmarket" / "models"))
    layout_dir = cache / "layout"
    return layout_dir.exists() and any(layout_dir.iterdir())


def _ai_available() -> bool:
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
