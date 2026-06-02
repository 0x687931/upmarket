#!/usr/bin/env python3
"""Fail when normal user-facing copy exposes internal toolkit names."""

from __future__ import annotations

import re
import sys
from pathlib import Path


SWIFT_STRING_RE = re.compile(r'"(?:\\.|[^"\\])*"')
FORBIDDEN_TERMS = [
    "python",
    "pythonkit",
    "docling",
    "pdfkit",
    "vision",
    "core ml",
    "coreml",
    "pdfium",
    "pymupdf",
    "pypdfium",
    "markitdown",
    "transformers",
    "torch",
    "mlx",
    "storekit",
    "feature flag",
    "ffprobe",
    "exiftool",
]
SWIFT_COPY_FILES = [
    Path("Upmarket/Upmarket/Domain/ConversionError.swift"),
    Path("Upmarket/Upmarket/Services/SupportReporter.swift"),
]
SWIFT_RUNTIME_LOG_FILES = [
    Path("Upmarket/Upmarket/Services/ConversionRunner.swift"),
    Path("Upmarket/Upmarket/Services/PythonBridge.swift"),
    Path("Upmarket/Upmarket/Services/PythonWorker.swift"),
]
SWIFT_COPY_DIRS = [
    Path("Upmarket/Upmarket/Views"),
]
TEXT_COPY_FILES = [
    Path(".github/ISSUE_TEMPLATE/crash-bug-report.yml"),
]


def swift_strings(path: Path) -> list[tuple[int, str]]:
    matches: list[tuple[int, str]] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        for match in SWIFT_STRING_RE.finditer(line):
            matches.append((line_number, match.group(0)))
    return matches


def text_lines(path: Path) -> list[tuple[int, str]]:
    return [
        (line_number, line)
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1)
    ]


def has_forbidden_term(text: str) -> str | None:
    normalized = text.lower()
    for term in FORBIDDEN_TERMS:
        if term in normalized:
            return term
    return None


def main() -> int:
    errors: list[str] = []
    swift_files = list(SWIFT_COPY_FILES)
    for directory in SWIFT_COPY_DIRS:
        swift_files.extend(sorted(directory.glob("*.swift")))

    for path in swift_files:
        if not path.exists():
            continue
        for line_number, value in swift_strings(path):
            if term := has_forbidden_term(value):
                errors.append(f"{path}:{line_number}: user-facing string exposes '{term}'")

    for path in SWIFT_RUNTIME_LOG_FILES:
        if not path.exists():
            continue
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if "AppLog." not in line:
                continue
            for match in SWIFT_STRING_RE.finditer(line):
                value = match.group(0)
                if term := has_forbidden_term(value):
                    errors.append(f"{path}:{line_number}: diagnostic log exposes '{term}'")

    for path in TEXT_COPY_FILES:
        if not path.exists():
            continue
        for line_number, value in text_lines(path):
            if term := has_forbidden_term(value):
                errors.append(f"{path}:{line_number}: user-facing text exposes '{term}'")

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print("ok: user-facing copy hides implementation toolkit details")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
