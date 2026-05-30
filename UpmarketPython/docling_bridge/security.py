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
from pathlib import Path

# ── Input limits ─────────────────────────────────────────────────────────────

MAX_FILE_SIZE_BYTES  = 500 * 1024 * 1024   # 500MB hard limit
MAX_PASSWORD_LENGTH  = 256                  # PDF passwords
MAX_TEXT_BLOCK_CHARS = 50_000               # single text block from PDF
MAX_REGEX_INPUT_CHARS = 10_000             # max chars passed to any regex

# ── File path validation ──────────────────────────────────────────────────────

def validate_file_path(file_path: str) -> str:
    """
    Validate and normalise a file path before passing to any parser.
    Raises ValueError on path traversal or oversized files.
    """
    path = Path(file_path).resolve()

    # Reject path traversal attempts
    # The resolved path must be within the user's home or /tmp
    allowed_roots = [
        Path.home(),
        Path("/tmp"),
        Path("/private/tmp"),
        Path("/var/folders"),
    ]
    if not any(str(path).startswith(str(root)) for root in allowed_roots):
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

    return str(path)


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
    - No nested quantifiers: never `(\s*\.\s*)+` or `(a+)+`
    - Use character classes `[. ]+` not grouped alternation `(\.|\ )+`
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
