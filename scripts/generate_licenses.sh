#!/bin/bash
# generate_licenses.sh
# Auto-generates the open-source license list shown in the About screen from the app's
# Swift package dependencies (Package.resolved) plus the vendored local packages.
# Run before each release or when dependencies change.
# Output: Upmarket/Upmarket/Resources/licenses.json
#
# Usage: ./scripts/generate_licenses.sh
#   Requires the SwiftPM checkouts to exist (build once, e.g. scripts/ci/gate.sh quick).
#   Override the checkouts dir with UPMARKET_SPM_CHECKOUTS.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT="Upmarket/Upmarket/Resources/licenses.json"
RESOLVED="Upmarket/Upmarket.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
CHECKOUTS="${UPMARKET_SPM_CHECKOUTS:-build/DerivedData/SourcePackages/checkouts}"

mkdir -p "$(dirname "$OUT")"
echo "==> Generating Swift dependency license list..."

CHECKOUTS="$CHECKOUTS" RESOLVED="$RESOLVED" OUT="$OUT" python3 - <<'PY'
import json, os, re
from pathlib import Path

resolved = Path(os.environ["RESOLVED"])
checkouts = Path(os.environ["CHECKOUTS"])
out_path = Path(os.environ["OUT"])

LICENSE_NAMES = ["LICENSE", "LICENSE.txt", "LICENSE.md", "LICENCE", "COPYING", "COPYING.txt"]


def detect_license(text: str) -> str:
    head = text[:4000].lower()
    if "apache license" in head and "version 2.0" in head:
        return "Apache-2.0"
    if "mit license" in head or "permission is hereby granted, free of charge" in head:
        return "MIT"
    if "bsd 3-clause" in head or "redistribution and use in source and binary forms" in head and "neither the name" in head:
        return "BSD-3-Clause"
    if "bsd 2-clause" in head:
        return "BSD-2-Clause"
    if "mozilla public license" in head:
        return "MPL-2.0"
    return "See project license"


def license_for(directory: Path) -> str:
    for name in LICENSE_NAMES:
        f = directory / name
        if f.is_file():
            return detect_license(f.read_text(encoding="utf-8", errors="ignore"))
    return "See project license"


entries = []

# Resolved (remote) Swift packages.
pins = json.loads(resolved.read_text()).get("pins", [])
for pin in pins:
    location = pin.get("location", "").removesuffix(".git")
    name = location.rsplit("/", 1)[-1] if location else pin.get("identity", "")
    state = pin.get("state", {})
    version = state.get("version") or (state.get("revision", "")[:8])
    checkout = checkouts / name
    license_id = license_for(checkout) if checkout.is_dir() else "See project license"
    entries.append({"name": name, "version": version, "license": license_id, "url": location})

# First-party vendored packages (SwiftOfficeMarkdown, UpmarketVLM) are proprietary
# Upmarket code, not third-party open source, so they are intentionally excluded here.

entries.sort(key=lambda e: e["name"].lower())
out_path.write_text(json.dumps(entries, indent=2) + "\n", encoding="utf-8")
print(f"==> Generated {len(entries)} license entries -> {out_path}")
PY
