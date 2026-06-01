#!/usr/bin/env python3
"""Guard release-critical paths that have regressed before."""

from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[2]


def require(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def main() -> int:
    errors: list[str] = []

    builder = (ROOT / "scripts" / "build_python_env.sh").read_text(encoding="utf-8")
    require(
        'Python.xcframework/macos-arm64_x86_64/Python.framework/Versions/$PYTHON_VERSION' in builder,
        "build_python_env.sh must rebuild the embedded Python.xcframework runtime",
        errors,
    )
    require(
        'SITE="$FRAMEWORK_ROOT/lib/python$PYTHON_VERSION/site-packages"' in builder,
        "build_python_env.sh must install dependencies into Python.xcframework site-packages",
        errors,
    )
    require(
        "python-stdlib" not in builder,
        "build_python_env.sh must not install into Upmarket/Python/python-stdlib",
        errors,
    )

    rc = (ROOT / ".github" / "workflows" / "release-candidate.yml").read_text(encoding="utf-8")
    require(
        'APP="$ARCHIVE_PATH/Products/Applications/Upmarket.app"' in rc,
        "release-candidate workflow must define the archived Upmarket.app path",
        errors,
    )
    require(
        'scripts/ci/verify_release_app.sh "$APP"' in rc,
        "release-candidate workflow must verify the archived app bundle",
        errors,
    )
    require(
        not re.search(r"smoke_convert_offline\.sh\s*(?:\n|$)", rc),
        "release-candidate workflow must not run offline smoke without an app bundle argument",
        errors,
    )

    vision = (ROOT / "Upmarket" / "Upmarket" / "Services" / "VisionOCR.swift").read_text(encoding="utf-8")
    require(
        "VisionProcessingLimits.renderSize(for: bounds, dpi: 150)" in vision,
        "VisionOCR must cap PDF render dimensions through VisionProcessingLimits before OCR",
        errors,
    )
    require(
        not re.search(r"let\s+scale\s*:\s*CGFloat\s*=\s*150\.0\s*/\s*72\.0", vision),
        "VisionOCR must not render PDF pages at uncapped raw 150 DPI",
        errors,
    )

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print("ok: release regression guards hold")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
