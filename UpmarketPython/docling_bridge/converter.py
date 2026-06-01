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

    # Formats Docling Enhanced supports (PDF + office documents only)
    # Audio, video, images always use fast path — Docling doesn't handle them
    ENHANCED_FORMATS = {'.pdf', '.docx', '.pptx', '.xlsx', '.html', '.htm',
                        '.md', '.asciidoc', '.epub', '.xml'}
    can_use_enhanced = suffix in ENHANCED_FORMATS

    # Route to appropriate pipeline
    try:
        if use_ai and can_use_enhanced:
            if not _ai_available():
                return _error("Upmarket AI model is not downloaded or failed validation. Download it again from Settings > Models.")
            return _convert_ai(path, opts)

        if suffix == ".pdf" and use_enhanced and _enhanced_available():
            return _convert_enhanced(path, opts)

        if suffix == ".pdf":
            return _convert_fast_pdf(path, password)

        # Non-PDF office formats: use enhanced if available and format is supported
        if use_enhanced and _enhanced_available() and can_use_enhanced:
            return _convert_enhanced(path, opts)

        # All other formats (audio, video, images, CSV, etc): always fast path
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
    """
    Fast path for non-PDF formats.
    Routes by extension to the best available handler:
      - Images (WEBP, TIF, BMP, GIF): Pillow metadata + OCR description
      - Audio/Video (FLAC, AVI, MOV + all others): ffprobe metadata + pydub waveform info
      - Everything else: markitdown (MIT, Microsoft) — DOCX, PPTX, XLSX, HTML, CSV, EPUB
    """
    suffix = path.suffix.lower()

    # Images markitdown can't handle — use Pillow
    if suffix in ('.webp', '.tif', '.tiff', '.bmp', '.gif'):
        return _convert_image_pillow(path)

    # Audio/video — always use ffprobe for metadata (never markitdown's whisper/SR path)
    # markitdown's audio transcription requires whisper/speech_recognition and fails on silence
    if suffix in ('.flac', '.avi', '.mov', '.ogg', '.aac', '.wma', '.wmv', '.mkv', '.m4v',
                  '.wav', '.mp3', '.m4a', '.mp4', '.mpeg', '.webm'):
        return _convert_media_ffprobe(path)

    # Everything else: markitdown — with graceful partial-content fallback
    try:
        from markitdown import MarkItDown
        md_converter = MarkItDown()
        result = md_converter.convert(str(path))
        markdown = result.text_content or ""
        return _success(markdown, 0, path, pipeline="fast")
    except Exception as e:
        suffix_upper = path.suffix.upper().lstrip(".")
        err_msg = str(e)

        # Pillow fallback for any image format markitdown fails on
        if suffix in ('.png', '.jpg', '.jpeg'):
            return _convert_image_pillow(path)

        # DOCX with external images: mammoth fails on missing image references.
        # Try extracting text-only by stripping the problematic relationship.
        if suffix == '.docx' and ('KeyError' in err_msg or 'rId' in err_msg):
            return _convert_docx_text_only(path)

        # PPTX with unrecognized shapes: extract what we can, skip bad slides.
        if suffix == '.pptx' and 'NotImplementedError' in err_msg:
            return _convert_pptx_safe(path)

        print(f"[Upmarket] markitdown error for {suffix_upper}: {e}", file=sys.stderr)
        return _error(f"Upmarket couldn't convert this {suffix_upper} file. Try downloading the Enhanced pipeline for better results.")


def _convert_docx_text_only(path: Path) -> dict:
    """Extract text from DOCX, skipping external images that cause mammoth to fail."""
    try:
        import zipfile, xml.etree.ElementTree as ET

        NS = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
        lines = []
        with zipfile.ZipFile(str(path)) as z:
            with z.open('word/document.xml') as f:
                tree = ET.parse(f)
                for para in tree.findall(f'.//{NS}p'):
                    text = ''.join(t.text or '' for t in para.findall(f'.//{NS}t'))
                    if text.strip():
                        lines.append(text.strip())

        return _success('\n\n'.join(lines), 0, path, pipeline="fast")
    except Exception as e:
        print(f"[Upmarket] DOCX text-only fallback failed: {e}", file=sys.stderr)
        return _error("Upmarket couldn't convert this Word document.")


def _convert_pptx_safe(path: Path) -> dict:
    """Extract text from PPTX, skipping slides with unrecognized shape types."""
    try:
        from pptx import Presentation
        from pptx.util import Pt

        prs = Presentation(str(path))
        slides_md = []
        for i, slide in enumerate(prs.slides):
            lines = []
            for shape in slide.shapes:
                try:
                    if hasattr(shape, 'text') and shape.text.strip():
                        lines.append(shape.text.strip())
                except Exception:
                    pass  # skip unrecognized shapes
            if lines:
                slides_md.append(f"## Slide {i+1}\n\n" + '\n\n'.join(lines))

        return _success('\n\n'.join(slides_md), len(prs.slides), path, pipeline="fast")
    except Exception as e:
        print(f"[Upmarket] PPTX safe fallback failed: {e}", file=sys.stderr)
        return _error("Upmarket couldn't convert this PowerPoint file.")


def _convert_image_pillow(path: Path) -> dict:
    """Extract image metadata and description via Pillow + optional exiftool."""
    try:
        from PIL import Image
        import subprocess, json

        img = Image.open(str(path))
        width, height = img.size
        mode = img.mode
        fmt = img.format or path.suffix.lstrip('.').upper()

        lines = [
            f"# Image: {path.name}",
            f"",
            f"**Format:** {fmt}  ",
            f"**Dimensions:** {width} × {height} px  ",
            f"**Color mode:** {mode}  ",
        ]

        # Try exiftool for rich metadata
        try:
            result = subprocess.run(
                ['exiftool', '-json', '-q', str(path)],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                meta = json.loads(result.stdout)[0]
                interesting = ['Make', 'Model', 'DateTimeOriginal', 'GPSLatitude', 'GPSLongitude',
                               'Title', 'Description', 'Author', 'Copyright', 'Software']
                exif_lines = []
                for key in interesting:
                    if key in meta:
                        exif_lines.append(f"**{key}:** {meta[key]}")
                if exif_lines:
                    lines.append("")
                    lines.append("## Metadata")
                    lines.extend(exif_lines)
        except Exception:
            pass

        return _success("\n".join(lines), 1, path, pipeline="fast")
    except Exception as e:
        print(f"[Upmarket] Pillow error: {e}", file=sys.stderr)
        return _error(f"Upmarket couldn't read this image file.")


def _convert_media_ffprobe(path: Path) -> dict:
    """Extract audio/video metadata using ffprobe."""
    import subprocess, json

    try:
        result = subprocess.run(
            ['ffprobe', '-v', 'quiet', '-print_format', 'json',
             '-show_format', '-show_streams', str(path)],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode != 0:
            raise RuntimeError(result.stderr)

        data = json.loads(result.stdout)
        fmt = data.get('format', {})
        streams = data.get('streams', [])

        duration = float(fmt.get('duration', 0))
        mins, secs = divmod(int(duration), 60)
        format_name = fmt.get('format_long_name', fmt.get('format_name', 'Unknown'))
        size_mb = int(fmt.get('size', 0)) / 1024 / 1024
        bitrate = int(fmt.get('bit_rate', 0)) // 1000

        lines = [
            f"# Media: {path.name}",
            "",
            f"**Format:** {format_name}  ",
            f"**Duration:** {mins}:{secs:02d}  ",
            f"**Size:** {size_mb:.1f} MB  ",
        ]
        if bitrate:
            lines.append(f"**Bitrate:** {bitrate} kbps  ")

        # Stream details
        for stream in streams:
            codec = stream.get('codec_type', 'unknown')
            codec_name = stream.get('codec_name', 'unknown')
            if codec == 'audio':
                sample_rate = stream.get('sample_rate', '?')
                channels = stream.get('channels', '?')
                lines.append(f"**Audio:** {codec_name}, {sample_rate}Hz, {channels}ch  ")
            elif codec == 'video':
                w = stream.get('width', '?')
                h = stream.get('height', '?')
                fps = stream.get('avg_frame_rate', '?')
                lines.append(f"**Video:** {codec_name}, {w}×{h}, {fps}fps  ")

        # Tags (title, artist, album etc)
        tags = fmt.get('tags', {})
        tag_keys = ['title', 'artist', 'album', 'date', 'comment', 'description']
        tag_lines = [f"**{k.title()}:** {tags[k]}" for k in tag_keys if k in tags]
        if tag_lines:
            lines.append("")
            lines.append("## Tags")
            lines.extend(tag_lines)

        return _success("\n".join(lines), 1, path, pipeline="fast")

    except Exception as e:
        print(f"[Upmarket] ffprobe error: {e}", file=sys.stderr)
        return _error(f"Upmarket couldn't read this media file.")


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
    result = _convert_enhanced(path, {**opts, "use_vlm": True})
    result["pipeline"] = "ai"
    return result


# MARK: - Availability checks

def _enhanced_available() -> bool:
    try:
        from upmarket_models.model_manager import model_available
        return model_available("layout")
    except Exception:
        return False


def _ai_available() -> bool:
    try:
        from upmarket_models.model_manager import model_available
        return model_available("upmarket_ai")
    except Exception:
        return False


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
