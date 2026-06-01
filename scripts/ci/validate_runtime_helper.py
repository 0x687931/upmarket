#!/usr/bin/env python3
"""Validate the isolated runtime helper target and optional built app packaging."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path


PROJECT = Path("Upmarket/Upmarket.xcodeproj/project.pbxproj")
HELPER_SOURCE = Path("Upmarket/UpmarketRuntimeHelper/main.swift")
HELPER_ENTITLEMENTS = Path("Upmarket/UpmarketRuntimeHelper/UpmarketRuntimeHelper.entitlements")
VENDORED_PYTHONKIT_NOTE = Path("Upmarket/Vendor/PythonKit/UPMARKET_VENDOR.md")


def fail(message: str) -> int:
    print(f"error: {message}", file=sys.stderr)
    return 1


def built_app_from_args() -> Path | None:
    if len(sys.argv) > 1:
        return Path(sys.argv[1])
    env_path = os.environ.get("UPMARKET_BUILT_APP")
    return Path(env_path) if env_path else None


def main() -> int:
    errors: list[str] = []
    project_text = PROJECT.read_text(encoding="utf-8")

    required_project_markers = [
        "UpmarketRuntimeHelper",
        "com.apple.product-type.tool",
        "Embed Runtime Helper",
        "UpmarketRuntimeHelper.entitlements",
        "PythonKit in Frameworks",
        "XCLocalSwiftPackageReference \"Vendor/PythonKit\"",
    ]
    for marker in required_project_markers:
        if marker not in project_text:
            errors.append(f"{PROJECT}: missing {marker}")

    if not HELPER_SOURCE.exists():
        errors.append(f"{HELPER_SOURCE}: helper source missing")
    elif "import PythonKit" not in HELPER_SOURCE.read_text(encoding="utf-8"):
        errors.append(f"{HELPER_SOURCE}: helper must own the runtime bridge import")

    if not HELPER_ENTITLEMENTS.exists():
        errors.append(f"{HELPER_ENTITLEMENTS}: helper entitlements missing")
    else:
        entitlements = HELPER_ENTITLEMENTS.read_text(encoding="utf-8")
        for marker in ["com.apple.security.app-sandbox", "com.apple.security.inherit"]:
            if marker not in entitlements:
                errors.append(f"{HELPER_ENTITLEMENTS}: missing {marker}")
        for marker in ["com.apple.security.network.client", "com.apple.security.application-groups"]:
            if marker in entitlements:
                errors.append(f"{HELPER_ENTITLEMENTS}: helper should inherit {marker} from the app sandbox")

    if not VENDORED_PYTHONKIT_NOTE.exists():
        errors.append(f"{VENDORED_PYTHONKIT_NOTE}: vendored runtime bridge dependency must record upstream provenance")

    app_path = built_app_from_args()
    if app_path:
        helper = app_path / "Contents" / "MacOS" / "UpmarketRuntimeHelper"
        if not helper.exists():
            errors.append(f"{helper}: embedded helper missing")
        elif os.access(helper, os.X_OK):
            request = json.dumps({"operation": "readiness"}).encode()
            result = subprocess.run(
                [str(helper), "--request-json-stdin"],
                input=request,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
                check=False,
            )
            if result.returncode != 0:
                errors.append(f"{helper}: readiness smoke exited {result.returncode}")
            elif b'"success":true' not in result.stdout:
                errors.append(f"{helper}: readiness smoke did not return success")
        else:
            errors.append(f"{helper}: embedded helper is not executable")

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print("ok: runtime helper boundary is configured")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
