"""
Thin wrapper around Docling for Swift interop via PythonKit.
All public functions return plain dicts (no custom types) for easy bridging.
"""

import os
import traceback
from pathlib import Path


def convert(file_path: str, options: dict | None = None) -> dict:
    """
    Convert a document to Markdown.

    Args:
        file_path: Absolute path to the input document.
        options: Optional dict with keys:
            - use_vlm (bool): Use SmolDocling VLM if available. Default False.
            - ocr (bool): Enable OCR for scanned PDFs. Default True.

    Returns:
        {
            "success": bool,
            "markdown": str,
            "metadata": { "pages": int, "format": str, "title": str },
            "error": str | None
        }
    """
    opts = options or {}

    try:
        from docling.document_converter import DocumentConverter, PdfFormatOption
        from docling.datamodel.base_models import InputFormat
        from docling.datamodel.pipeline_options import PdfPipelineOptions

        path = Path(file_path)
        if not path.exists():
            return _error("Upmarket couldn't find this file. Please try again.")

        pipeline_options = PdfPipelineOptions()
        pipeline_options.do_ocr = opts.get("ocr", True)
        pipeline_options.do_table_structure = True

        converter = DocumentConverter(
            format_options={
                InputFormat.PDF: PdfFormatOption(pipeline_options=pipeline_options)
            }
        )

        result = converter.convert(str(path))
        markdown = result.document.export_to_markdown()

        num_pages = result.document.num_pages()
        metadata = {
            "pages": num_pages if isinstance(num_pages, int) else 0,
            "format": path.suffix.lstrip(".").upper(),
            "title": getattr(result.document, "title", path.stem) or path.stem,
        }

        return {"success": True, "markdown": markdown, "metadata": metadata, "error": None}

    except Exception as e:
        # Log technical detail internally but never expose to user
        import sys
        print(f"[Upmarket] Conversion error: {type(e).__name__}: {e}", file=sys.stderr)
        return _error("Upmarket couldn't convert this document. The file may be damaged, password-protected, or in an unsupported format.")


def _error(message: str) -> dict:
    return {
        "success": False,
        "markdown": "",
        "metadata": {},
        "error": message,
    }
