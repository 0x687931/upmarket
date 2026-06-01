#!/usr/bin/env python3
"""Validate the lightweight monolith boundaries for P0-001."""

from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path("Upmarket/Upmarket")
VIEW_DIR = ROOT / "Views"
FORBIDDEN_IN_VIEWS = {
    "import PythonKit": "views must not import PythonKit",
    "Python.import": "views must not call Python modules",
    "NSOpenPanel(": "views must use FileAccessService for open panels",
    "NSSavePanel(": "views must use FileAccessService or SavePreference for save panels",
    "NSPasteboard.general": "views must use FileAccessService for pasteboard writes",
}


def main() -> int:
    errors: list[str] = []

    if (VIEW_DIR / "MenuBarView.swift").exists():
        errors.append("Views/MenuBarView.swift is an unused duplicate of MenuBarDropdown; do not restore it")

    for path in sorted(VIEW_DIR.glob("*.swift")):
        text = path.read_text(encoding="utf-8")
        for pattern, message in FORBIDDEN_IN_VIEWS.items():
            if pattern in text:
                errors.append(f"{path}: {message} ({pattern})")

    if not (ROOT / "Services" / "FileAccessService.swift").exists():
        errors.append("Services/FileAccessService.swift is required for AppKit file/pasteboard operations")

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print("ok: architecture boundaries hold")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
