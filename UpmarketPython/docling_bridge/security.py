"""
Upmarket security hardening for the Python bridge layer.

Guards against:
- ReDoS: Regular Expression Denial of Service
- Buffer overruns: unbounded input to C extensions
- ACE: Arbitrary Code Execution via malicious document content
- Path traversal: escaped file paths

All user-supplied content (file paths, passwords, document text) passes
through this module before reaching any parser or regex.
"""

import re
import os
import sys
import zipfile
import socket
from pathlib import Path
from zipfile import BadZipFile

# ── Input limits ─────────────────────────────────────────────────────────────

MAX_FILE_SIZE_BYTES  = 500 * 1024 * 1024   # 500MB hard limit
MAX_PASSWORD_LENGTH  = 256                  # PDF passwords
MAX_TEXT_BLOCK_CHARS = 50_000               # single text block from PDF
MAX_REGEX_INPUT_CHARS = 10_000             # max chars passed to any regex
MAX_ARCHIVE_ENTRIES = 1_000
MAX_ARCHIVE_UNCOMPRESSED_BYTES = 250 * 1024 * 1024
MAX_ARCHIVE_COMPRESSION_RATIO = 100
MAX_PDF_PAGES = 1_000
MAX_PDF_PAGE_SIDE_POINTS = 14_400          # 200 inches at 72 dpi
MAX_PDF_PAGE_AREA_POINTS = 50_000_000
MAX_IMAGE_PIXELS = 40_000_000
MAX_IMAGE_SIDE = 32_768
ARCHIVE_EXTENSIONS = {".zip", ".docx", ".pptx", ".xlsx", ".epub"}
PDF_EXTENSIONS = {".pdf"}
IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".tif", ".tiff", ".bmp", ".gif"}
TEXT_EXTENSIONS = {".txt", ".md", ".csv", ".json", ".xml", ".html", ".htm", ".asciidoc", ".vtt"}
AUDIO_VIDEO_EXTENSIONS = {
    ".flac", ".avi", ".mov", ".ogg", ".aac", ".wma", ".wmv", ".mkv", ".m4v",
    ".wav", ".mp3", ".m4a", ".mp4", ".mpeg", ".webm",
}
OOXML_EXTENSIONS = {".docx", ".pptx", ".xlsx"}
_RUNTIME_SANDBOX_INSTALLED = False


def install_runtime_sandbox() -> None:
    """
    Install process-local guards for the embedded runtime.

    macOS App Sandbox remains the hard boundary. These guards keep bundled
    Python conversion code in the intended lane: no child processes and no
    network during conversion. Model download is the only operation that may
    enable network with UPMARKET_ALLOW_NETWORK=1.
    """
    global _RUNTIME_SANDBOX_INSTALLED
    if _RUNTIME_SANDBOX_INSTALLED:
        return
    if os.environ.get("UPMARKET_RUNTIME_SANDBOX") != "1":
        return

    _RUNTIME_SANDBOX_INSTALLED = True
    sys.addaudithook(_runtime_audit_hook)
    _patch_runtime_escape_hatches()


def _runtime_audit_hook(event: str, args: tuple) -> None:
    blocked_events = {
        "os.system",
        "os.fork",
        "os.forkpty",
        "os.posix_spawn",
        "subprocess.Popen",
        "pty.spawn",
    }
    if event in blocked_events:
        raise PermissionError(f"Runtime sandbox blocked {event}")
    if event.startswith("socket.") and os.environ.get("UPMARKET_ALLOW_NETWORK") != "1":
        raise PermissionError("Runtime sandbox blocked network access")


def _patch_runtime_escape_hatches() -> None:
    original_socket = socket.socket

    def guarded_socket(*args, **kwargs):
        if os.environ.get("UPMARKET_ALLOW_NETWORK") != "1":
            raise PermissionError("Runtime sandbox blocked network access")
        return original_socket(*args, **kwargs)

    socket.socket = guarded_socket

# ── File path validation ──────────────────────────────────────────────────────

def validate_file_path(file_path: str) -> str:
    """
    Validate and normalise a file path before passing to any parser.
    Raises ValueError on path traversal or oversized files.
    """
    path = Path(file_path).resolve()

    # Reject path traversal attempts. Swift copies user-selected files into an
    # app-owned per-job workspace and passes that root through the environment.
    configured_roots = os.environ.get("UPMARKET_ALLOWED_INPUT_ROOTS", "")
    allowed_roots = [
        Path(root)
        for root in configured_roots.split(os.pathsep)
        if root
    ]
    if not allowed_roots:
        raise ValueError("No allowed input workspace configured")
    if not any(_is_within(path, root) for root in allowed_roots):
        raise ValueError(f"File path outside allowed directories: {path}")

    if not path.exists():
        raise ValueError(f"File not found: {path}")

    if not path.is_file():
        raise ValueError(f"Not a file: {path}")

    size = path.stat().st_size
    if size > MAX_FILE_SIZE_BYTES:
        raise ValueError(
            f"File too large: {size / 1024 / 1024:.1f}MB "
            f"(max {MAX_FILE_SIZE_BYTES // 1024 // 1024}MB)"
        )
    suffix = path.suffix.lower()
    validate_file_signature(path, suffix)
    if suffix in ARCHIVE_EXTENSIONS:
        validate_archive_file(path)
    if suffix in PDF_EXTENSIONS:
        validate_pdf_file(path)
    if suffix in IMAGE_EXTENSIONS:
        validate_image_file(path)

    return str(path)


def validate_file_signature(path: Path, suffix: str | None = None) -> None:
    """
    Reject obvious extension/content mismatches before dispatching parsers.

    This is intentionally conservative and cheap. It is not a full MIME
    detector; it blocks the common malicious case where a parser is selected
    by a trusted extension but the bytes are a different format.
    """
    suffix = suffix or path.suffix.lower()
    with path.open("rb") as handle:
        header = handle.read(4096)

    if suffix in PDF_EXTENSIONS:
        if b"%PDF-" not in header[:1024]:
            raise ValueError("File extension does not match PDF content")
        return

    if suffix in ARCHIVE_EXTENSIONS:
        if not zipfile.is_zipfile(path):
            raise ValueError("File extension does not match ZIP-based content")
        return

    if suffix in IMAGE_EXTENSIONS:
        if not _looks_like_image(header, suffix):
            raise ValueError("File extension does not match image content")
        return

    if suffix in AUDIO_VIDEO_EXTENSIONS:
        if not _looks_like_media(header, suffix):
            raise ValueError("File extension does not match media content")
        return

    if suffix in TEXT_EXTENSIONS:
        validate_text_file_header(header, suffix)


def validate_text_file_header(header: bytes, suffix: str) -> None:
    if b"\x00" in header:
        raise ValueError("Text file contains binary data")
    lowered = header.lower()
    if suffix == ".xml" and (b"<!entity" in lowered or b"<!doctype" in lowered):
        raise ValueError("XML files with DTD or entity declarations are not supported")


def _looks_like_image(header: bytes, suffix: str) -> bool:
    if suffix == ".png":
        return header.startswith(b"\x89PNG\r\n\x1a\n")
    if suffix in {".jpg", ".jpeg"}:
        return header.startswith(b"\xff\xd8\xff")
    if suffix == ".webp":
        return header.startswith(b"RIFF") and header[8:12] == b"WEBP"
    if suffix in {".tif", ".tiff"}:
        return header.startswith((b"II*\x00", b"MM\x00*"))
    if suffix == ".bmp":
        return header.startswith(b"BM")
    if suffix == ".gif":
        return header.startswith((b"GIF87a", b"GIF89a"))
    return True


def _looks_like_media(header: bytes, suffix: str) -> bool:
    if suffix == ".mp3":
        return header.startswith(b"ID3") or header.startswith((b"\xff\xfb", b"\xff\xf3", b"\xff\xf2"))
    if suffix == ".wav":
        return header.startswith(b"RIFF") and header[8:12] == b"WAVE"
    if suffix == ".flac":
        return header.startswith(b"fLaC")
    if suffix == ".ogg":
        return header.startswith(b"OggS")
    if suffix in {".mp4", ".m4a", ".m4v", ".mov"}:
        return len(header) >= 12 and header[4:8] == b"ftyp"
    if suffix in {".webm", ".mkv"}:
        return header.startswith(b"\x1a\x45\xdf\xa3")
    if suffix == ".avi":
        return header.startswith(b"RIFF") and header[8:12] == b"AVI "
    if suffix in {".aac", ".wma", ".wmv", ".mpeg"}:
        return True
    return True


def validate_archive_file(path: Path) -> None:
    """
    Preflight archives before handing them to converters.

    This does not extract anything. It rejects common zip-bomb patterns:
    extreme compression ratios, excessive total expanded size, too many files,
    nested archives, and paths that would escape an extraction root.
    """
    try:
        with zipfile.ZipFile(path) as archive:
            infos = archive.infolist()
    except BadZipFile as exc:
        raise ValueError("Invalid ZIP archive") from exc

    if len(infos) > MAX_ARCHIVE_ENTRIES:
        raise ValueError(f"ZIP archive contains too many files (max {MAX_ARCHIVE_ENTRIES})")

    total_uncompressed = 0
    total_compressed = 0
    for info in infos:
        name = info.filename
        entry_path = Path(name)
        if info.is_dir():
            continue
        if entry_path.is_absolute() or ".." in entry_path.parts:
            raise ValueError("ZIP archive contains unsafe file paths")
        if entry_path.suffix.lower() in ARCHIVE_EXTENSIONS:
            raise ValueError("Nested ZIP archives are not supported")

        total_uncompressed += max(info.file_size, 0)
        total_compressed += max(info.compress_size, 0)
        if total_uncompressed > MAX_ARCHIVE_UNCOMPRESSED_BYTES:
            limit = MAX_ARCHIVE_UNCOMPRESSED_BYTES // 1024 // 1024
            raise ValueError(f"ZIP archive expands beyond {limit}MB")

    if total_uncompressed > 0:
        compressed = max(total_compressed, 1)
        ratio = total_uncompressed / compressed
        if ratio > MAX_ARCHIVE_COMPRESSION_RATIO:
            raise ValueError("ZIP archive compression ratio is unsafe")


def validate_pdf_file(path: Path) -> None:
    """Reject PDFs with pathological page counts or page dimensions."""
    try:
        import pypdfium2 as pdfium

        document = pdfium.PdfDocument(str(path))
    except Exception as exc:
        # Let the converter produce password/corruption-specific errors later.
        return

    try:
        page_count = len(document)
        if page_count > MAX_PDF_PAGES:
            raise ValueError(f"PDF contains too many pages (max {MAX_PDF_PAGES})")

        for index in range(page_count):
            page = document[index]
            try:
                width = float(page.get_width())
                height = float(page.get_height())
            finally:
                page.close()

            if width <= 0 or height <= 0 or not width == width or not height == height:
                raise ValueError("PDF contains invalid page dimensions")
            if width > MAX_PDF_PAGE_SIDE_POINTS or height > MAX_PDF_PAGE_SIDE_POINTS:
                raise ValueError("PDF page dimensions are too large to process safely")
            if width * height > MAX_PDF_PAGE_AREA_POINTS:
                raise ValueError("PDF page area is too large to process safely")
    finally:
        document.close()


def validate_image_file(path: Path) -> None:
    """Reject images whose declared dimensions would allocate unsafe memory."""
    try:
        from PIL import Image

        Image.MAX_IMAGE_PIXELS = MAX_IMAGE_PIXELS
        with Image.open(path) as image:
            width, height = image.size
            image.verify()
    except Exception as exc:
        log_security_event("IMAGE_VALIDATION_FAILED", f"{type(exc).__name__}: {exc}")
        raise ValueError("Invalid or unsafe image file") from exc

    if width <= 0 or height <= 0:
        raise ValueError("Image contains invalid dimensions")
    if width > MAX_IMAGE_SIDE or height > MAX_IMAGE_SIDE:
        raise ValueError("Image dimensions are too large to process safely")
    if width * height > MAX_IMAGE_PIXELS:
        raise ValueError("Image pixel count is too large to process safely")


def _is_within(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root.resolve())
        return True
    except ValueError:
        return False


def validate_password(password: str | None) -> str | None:
    """Validate PDF password length to prevent buffer overruns in C library."""
    if password is None:
        return None
    if len(password) > MAX_PASSWORD_LENGTH:
        raise ValueError(f"Password too long (max {MAX_PASSWORD_LENGTH} chars)")
    # Strip null bytes that could confuse C string handling
    return password.replace('\x00', '')


# ── Regex safety ──────────────────────────────────────────────────────────────

class SafeRegex:
    """
    Wrapper that enforces input length limits before any regex match.
    Prevents ReDoS by ensuring worst-case runtime is bounded.

    Rules for safe regex patterns (enforced by code review, not this class):
    - No nested quantifiers: never `(\\s*\\.\\s*)+` or `(a+)+`
    - Use character classes `[. ]+` not grouped alternation `(\\.|\\ )+`
    - Anchor patterns where possible: `^` and `$`
    - Prefer `re.match` (anchored) over `re.search` for validation
    """

    def __init__(self, pattern: str, flags: int = 0, max_input: int = MAX_REGEX_INPUT_CHARS):
        self._re = re.compile(pattern, flags)
        self._max_input = max_input

    def sub(self, repl: str, text: str) -> str:
        if len(text) > self._max_input:
            # Truncate rather than hang — document text capped, no data loss on structure
            text = text[:self._max_input]
        return self._re.sub(repl, text)

    def match(self, text: str) -> re.Match | None:
        if len(text) > self._max_input:
            return None
        return self._re.match(text)

    def search(self, text: str) -> re.Match | None:
        if len(text) > self._max_input:
            return None
        return self._re.search(text)


# ── ACE prevention ────────────────────────────────────────────────────────────

def sanitise_text_block(text: str) -> str:
    """
    Sanitise a text block extracted from a PDF before further processing.

    PDF text content can contain:
    - Null bytes that confuse string handling
    - Control characters that could affect terminal output
    - Extremely long lines that cause quadratic string operations

    Does NOT strip Unicode or non-ASCII — that would corrupt non-Latin docs.
    """
    if not text:
        return ""

    # Hard cap on block size
    if len(text) > MAX_TEXT_BLOCK_CHARS:
        text = text[:MAX_TEXT_BLOCK_CHARS]

    # Remove null bytes and non-printable ASCII control chars (except \n, \t)
    # Keep Unicode intact — needed for CJK, Arabic, Hebrew etc.
    text = ''.join(
        c for c in text
        if c == '\n' or c == '\t' or (ord(c) >= 32 and ord(c) != 127)
    )

    return text


# ── Audit log ─────────────────────────────────────────────────────────────────

def log_security_event(event_type: str, detail: str) -> None:
    """Log security-relevant events to stderr for the app to capture."""
    print(f"[Upmarket:Security] {event_type}: {detail}", file=sys.stderr)
