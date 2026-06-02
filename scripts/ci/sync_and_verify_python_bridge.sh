#!/usr/bin/env bash
set -euo pipefail

SITE="${1:-Upmarket/Python/Python.xcframework/macos-arm64_x86_64/Python.framework/Versions/3.12/lib/python3.12/site-packages}"

scripts/ci/sync_python_bridge.sh "$SITE" >/dev/null

python3 - "$SITE" <<'PY'
from __future__ import annotations

import filecmp
import sys
from pathlib import Path

site = Path(sys.argv[1])
pairs = [
    (Path("UpmarketPython/docling_bridge"), site / "docling_bridge"),
    (Path("UpmarketPython/models"), site / "upmarket_models"),
]

errors: list[str] = []
for source_dir, bundled_dir in pairs:
    for source in sorted(source_dir.glob("*.py")):
        bundled = bundled_dir / source.name
        if not bundled.exists():
            errors.append(f"missing bundled bridge file: {bundled}")
        elif not filecmp.cmp(source, bundled, shallow=False):
            errors.append(f"bundled bridge file is stale: {bundled}")

security = site / "docling_bridge" / "security.py"
if "def install_runtime_sandbox(" not in security.read_text(encoding="utf-8"):
    errors.append("docling_bridge.security.install_runtime_sandbox is missing from bundled runtime")

if errors:
    raise SystemExit("error: " + "\nerror: ".join(errors))
PY

echo "ok: first-party Python bridge synced and verified"
