#!/usr/bin/env python3
"""Validate the lightweight monolith boundaries for P0-001."""

from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path("Upmarket/Upmarket")
VIEW_DIR = ROOT / "Views"
APP_SOURCE = ROOT / "UpmarketApp.swift"
APPROVED_PYTHONKIT_IMPORTS: set[Path] = set()
APPROVED_PYTHON_CALLS = APPROVED_PYTHONKIT_IMPORTS
HELPER_SOURCE = Path("Upmarket/UpmarketRuntimeHelper/main.swift")
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
FORBIDDEN_APP_SCENE_WORKAROUNDS = {
    "orderOut(nil)": "app scene must not create then hide launch windows",
    ".defaultSize(width: 0": "app scene must not use zero-size hidden windows",
    ".defaultSize(width: 0, height: 0)": "app scene must not use zero-size hidden windows",
    ".frame(width: 0": "app scene must not use zero-size hidden views as window placeholders",
    ".frame(width: 0, height: 0)": "app scene must not use zero-size hidden views as window placeholders",
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

    if APP_SOURCE.exists():
        app_text = APP_SOURCE.read_text(encoding="utf-8")
        for pattern, message in FORBIDDEN_APP_SCENE_WORKAROUNDS.items():
            if pattern in app_text:
                errors.append(f"{APP_SOURCE}: {message} ({pattern})")
        if "WindowGroup" in app_text and "MenuBarExtra" in app_text:
            errors.append(
                f"{APP_SOURCE}: menu-bar app must not restore a placeholder WindowGroup; "
                "use explicit Window scenes or document a real primary window"
            )
    else:
        errors.append(f"{APP_SOURCE}: app source is missing")

    for path in sorted(ROOT.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        if "import PythonKit" in text and path not in APPROVED_PYTHONKIT_IMPORTS:
            errors.append(f"{path}: PythonKit imports must stay behind PythonBridge/PythonWorker")
        if "Python.import" in text and path not in APPROVED_PYTHON_CALLS:
            errors.append(f"{path}: Python.import calls must stay behind PythonBridge/PythonWorker")
        if path.parent == ROOT / "Services" and "print(" in text:
            errors.append(f"{path}: service diagnostics must use AppLog/OSLog, not print")

    if not (ROOT / "Services" / "FileAccessService.swift").exists():
        errors.append("Services/FileAccessService.swift is required for AppKit file/pasteboard operations")

    if not HELPER_SOURCE.exists():
        errors.append("UpmarketRuntimeHelper/main.swift is required for isolated runtime work")
    elif "import PythonKit" not in HELPER_SOURCE.read_text(encoding="utf-8"):
        errors.append("UpmarketRuntimeHelper/main.swift must own the only PythonKit import")

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print("ok: architecture boundaries hold")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
