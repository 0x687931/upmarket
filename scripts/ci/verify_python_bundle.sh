#!/usr/bin/env bash
set -euo pipefail

SITE="${1:-Upmarket/Python/Python.xcframework/macos-arm64_x86_64/Python.framework/Versions/3.12/lib/python3.12/site-packages}"
LOCK="requirements.txt"

if [[ ! -d "$SITE" ]]; then
  echo "error: bundled Python site-packages not found at $SITE"
  exit 1
fi

scripts/ci/validate_dependency_lock.py --current "$LOCK" --candidate requirements-candidate.txt >/dev/null

required_paths=(
  "$SITE/docling_bridge"
  "$SITE/docling_bridge/converter.py"
  "$SITE/docling_bridge/security.py"
  "$SITE/upmarket_models"
  "$SITE/upmarket_models/model_manager.py"
)

for path in "${required_paths[@]}"; do
  if [[ ! -e "$path" ]]; then
    echo "error: missing bundled Python path: $path"
    exit 1
  fi
done

python3 - "$SITE" <<'PY'
from __future__ import annotations

import filecmp
import re
import sys
from pathlib import Path

site = Path(sys.argv[1])
python_version_match = re.search(r"/python(\d+)\.(\d+)/site-packages$", str(site))
expected_tag = None
if python_version_match:
    expected_tag = f"cpython-{python_version_match.group(1)}{python_version_match.group(2)}"

pairs = [
    (Path("UpmarketPython/docling_bridge"), site / "docling_bridge"),
    (Path("UpmarketPython/models"), site / "upmarket_models"),
]

errors = []
if not expected_tag:
    errors.append(f"could not infer Python ABI tag from bundled site path: {site}")

extension_tag_re = re.compile(r"\.(cpython-\d+)-")
for extension in sorted(site.rglob("*.so")):
    match = extension_tag_re.search(extension.name)
    if match and match.group(1) != expected_tag:
        errors.append(f"native extension ABI mismatch: {extension} uses {match.group(1)}, expected {expected_tag}")

for source_dir, bundled_dir in pairs:
    for source in sorted(source_dir.glob("*.py")):
        bundled = bundled_dir / source.name
        if not bundled.exists():
            errors.append(f"missing bundled bridge file: {bundled}")
        elif not filecmp.cmp(source, bundled, shallow=False):
            errors.append(f"bundled bridge file is stale: {bundled}")

if errors:
    raise SystemExit("error: " + "\nerror: ".join(errors))
PY

CHECK_VENV="$(mktemp -d "${TMPDIR:-/tmp}/upmarket-pip-check.XXXXXX")"
trap 'rm -rf "$CHECK_VENV"' EXIT
python3 -m venv "$CHECK_VENV"
PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_CACHE_DIR="$CHECK_VENV/pip-cache" PYTHONPATH="$SITE" \
  "$CHECK_VENV/bin/python" -m pip check >/dev/null
trap - EXIT
rm -rf "$CHECK_VENV"

PYTHONPATH="$SITE" HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 python3 - "$SITE" "$LOCK" <<'PY'
import importlib
import importlib.util
from importlib import metadata
import os
from pathlib import Path
import re
import sys

from packaging.requirements import Requirement
from packaging.utils import canonicalize_name

modules = [
    "docling_bridge.converter",
    "docling_bridge.security",
    "upmarket_models.model_manager",
]

for module in modules:
    importlib.import_module(module)

site_root = sys.argv[1]
lock = Path(sys.argv[2])
distributions = list(metadata.distributions(path=[site_root]))
versions = {
    canonicalize_name(distribution.metadata["Name"]): distribution.version
    for distribution in distributions
}

name_re = re.compile(r"^\s*([A-Za-z0-9_.-]+)\s*==\s*([^,\s]+)")
for raw in lock.read_text(encoding="utf-8").splitlines():
    line = raw.split("#", 1)[0].strip()
    if not line:
        continue
    match = name_re.match(line)
    if not match:
        continue
    name, expected = match.group(1), match.group(2)
    actual = versions.get(canonicalize_name(name))
    if actual is None:
        raise SystemExit(f"error: bundled dependency missing: {name}")
    if actual != expected:
        raise SystemExit(f"error: bundled dependency drift: {name} {actual} != {expected}")

for distribution in distributions:
    parent = distribution.metadata["Name"]
    for raw_requirement in distribution.requires or []:
        requirement = Requirement(raw_requirement)
        if requirement.marker and not requirement.marker.evaluate({"extra": ""}):
            continue
        actual = versions.get(canonicalize_name(requirement.name))
        if actual is None:
            raise SystemExit(f"error: bundled dependency missing: {parent} requires {requirement}")
        if requirement.specifier and actual not in requirement.specifier:
            raise SystemExit(
                f"error: bundled dependency conflict: {parent} requires {requirement}, found {actual}"
            )

for forbidden in (
    "fitz",
    "pymupdf",
    "pymupdf4llm",
    "paddleocr",
    "paddle",
    "poppler",
):
    spec = importlib.util.find_spec(forbidden)
    origin = getattr(spec, "origin", "") if spec else ""
    if origin and origin.startswith(site_root):
        raise SystemExit(f"error: internal/reference-only benchmark package present in bundled runtime: {forbidden}")

print("ok: bundled Python bridge imports, pins, and dependency graph")
PY
