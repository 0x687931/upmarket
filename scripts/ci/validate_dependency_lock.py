#!/usr/bin/env python3
"""Validate exact-pinned current and candidate Python dependency states."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


NAME_RE = re.compile(r"^\s*([A-Za-z0-9_.-]+)\s*(.*)$")
EXACT_RE = re.compile(r"^==\s*([^,\s]+)$")
FORBIDDEN = (">=", "<=", "~=", "!=", ">", "<", "*")
FORBIDDEN_PACKAGES = {
    "pymupdf": "PyMuPDF is AGPL/commercial and must not ship in the paid release runtime without a commercial license ADR.",
    "pymupdf4llm": "pymupdf4llm depends on PyMuPDF licensing and must not ship in the paid release runtime without a commercial license ADR.",
    "fitz": "fitz/PyMuPDF must not ship in the paid release runtime without a commercial license ADR.",
    "rapidocr": "RapidOCR is an internal/reference benchmark pathway only until an ADR approves release packaging.",
    "rapidocr-onnxruntime": "RapidOCR is an internal/reference benchmark pathway only until an ADR approves release packaging.",
    "paddleocr": "PaddleOCR is an internal/reference benchmark pathway only until an ADR approves release packaging.",
    "paddlepaddle": "PaddleOCR/PaddlePaddle is an internal/reference benchmark pathway only until an ADR approves release packaging.",
    "python-poppler": "Poppler is an internal/reference benchmark pathway only until an ADR approves release packaging.",
    "poppler": "Poppler is an internal/reference benchmark pathway only until an ADR approves release packaging.",
}


def parse(path: Path) -> tuple[dict[str, str], list[str]]:
    packages: dict[str, str] = {}
    errors: list[str] = []
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("-"):
            errors.append(f"{path}:{number}: option lines are not allowed in release dependency locks")
            continue
        match = NAME_RE.match(line)
        if not match:
            errors.append(f"{path}:{number}: could not parse requirement")
            continue
        name, specifier = match.group(1), match.group(2).strip()
        normalized = name.lower().replace("_", "-")
        if normalized in FORBIDDEN_PACKAGES:
            errors.append(f"{path}:{number}: forbidden dependency {name}: {FORBIDDEN_PACKAGES[normalized]}")
            continue
        if normalized in packages:
            errors.append(f"{path}:{number}: duplicate dependency {name}")
            continue
        if any(token in specifier for token in FORBIDDEN) and not specifier.startswith("=="):
            errors.append(f"{path}:{number}: dependency must be exact-pinned with ==, got {specifier or 'unbounded'}")
            continue
        exact = EXACT_RE.match(specifier)
        if not exact:
            errors.append(f"{path}:{number}: dependency must be exact-pinned with ==, got {specifier or 'unbounded'}")
            continue
        packages[normalized] = exact.group(1)
    return packages, errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--current", default="requirements.txt")
    parser.add_argument("--candidate", default="requirements-candidate.txt")
    args = parser.parse_args()

    current_path = Path(args.current)
    candidate_path = Path(args.candidate)
    errors: list[str] = []

    for path in (current_path, candidate_path):
        if not path.exists():
            errors.append(f"missing dependency lock: {path}")

    if errors:
        print("\n".join(f"error: {error}" for error in errors))
        return 1

    current, current_errors = parse(current_path)
    candidate, candidate_errors = parse(candidate_path)
    errors.extend(current_errors)
    errors.extend(candidate_errors)

    if current.keys() != candidate.keys():
        missing_candidate = sorted(current.keys() - candidate.keys())
        missing_current = sorted(candidate.keys() - current.keys())
        if missing_candidate:
            errors.append(f"candidate lock missing current dependencies: {', '.join(missing_candidate)}")
        if missing_current:
            errors.append(f"current lock missing candidate dependencies: {', '.join(missing_current)}")

    if errors:
        print("\n".join(f"error: {error}" for error in errors))
        return 1

    changed = [name for name in sorted(current) if current[name] != candidate[name]]
    state = "candidate-diff" if changed else "candidate-matches-current"
    print(f"ok: dependency locks exact-pinned ({len(current)} packages, {state})")
    if changed:
        print("candidate changes: " + ", ".join(changed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
