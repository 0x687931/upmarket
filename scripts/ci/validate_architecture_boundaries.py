#!/usr/bin/env python3
"""Validate the lightweight monolith boundaries for P0-001."""

from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path("Upmarket/Upmarket")
VIEW_DIR = ROOT / "Views"
APPROVED_PYTHONKIT_IMPORTS = {
    ROOT / "Services" / "PythonBridge.swift",
    ROOT / "Services" / "PythonWorker.swift",
}
REQUIRED_CORE_FILES = {
    ROOT / "Domain" / "ConversionJob.swift",
    ROOT / "Domain" / "ConversionResult.swift",
    ROOT / "Domain" / "ConversionError.swift",
    ROOT / "Services" / "ConversionQueue.swift",
    ROOT / "Services" / "ConversionRunner.swift",
    ROOT / "Services" / "PythonWorker.swift",
}
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

    if (ROOT / "Services" / "ConversionService.swift").exists():
        errors.append("Services/ConversionService.swift must not be restored; use ConversionQueue and ConversionRunner")

    for required in sorted(REQUIRED_CORE_FILES):
        if not required.exists():
            errors.append(f"{required}: required minimalist conversion core file is missing")

    for path in sorted(VIEW_DIR.glob("*.swift")):
        text = path.read_text(encoding="utf-8")
        for pattern, message in FORBIDDEN_IN_VIEWS.items():
            if pattern in text:
                errors.append(f"{path}: {message} ({pattern})")

    for path in sorted(ROOT.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        if "import PythonKit" in text and path not in APPROVED_PYTHONKIT_IMPORTS:
            errors.append(f"{path}: PythonKit imports must stay behind PythonBridge/PythonWorker")

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
