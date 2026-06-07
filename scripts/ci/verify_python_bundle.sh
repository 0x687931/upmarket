#!/usr/bin/env bash
set -euo pipefail

SITE="${1:-Upmarket/Python/Python.xcframework/macos-arm64_x86_64/Python.framework/Versions/3.12/lib/python3.12/site-packages}"
LOCK="requirements.txt"
STDLIB="$(dirname "$SITE")"
SITE_PYTHON_VERSION="$(printf '%s\n' "$SITE" | sed -nE 's#.*lib/python([0-9]+[.][0-9]+)/site-packages$#\1#p')"
PYTHON_CHECK_BIN="${PYTHON_CHECK_BIN:-python$SITE_PYTHON_VERSION}"

if [[ ! -d "$SITE" ]]; then
  echo "error: bundled Python site-packages not found at $SITE"
  exit 1
fi

if [[ -z "$SITE_PYTHON_VERSION" ]]; then
  echo "error: unable to infer bundled Python version from $SITE"
  exit 1
fi

if ! command -v "$PYTHON_CHECK_BIN" >/dev/null 2>&1; then
  echo "error: $PYTHON_CHECK_BIN is required to verify bundled Python $SITE_PYTHON_VERSION extensions"
  exit 1
fi

ACTUAL_CHECK_VERSION="$("$PYTHON_CHECK_BIN" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
if [[ "$ACTUAL_CHECK_VERSION" != "$SITE_PYTHON_VERSION" ]]; then
  echo "error: verifier interpreter must be Python $SITE_PYTHON_VERSION, got $ACTUAL_CHECK_VERSION from $PYTHON_CHECK_BIN"
  exit 1
fi

scripts/ci/validate_dependency_lock.py --current "$LOCK" --candidate requirements-candidate.txt >/dev/null

required_paths=(
  "$STDLIB/encodings/idna.py"
  "$STDLIB/encodings/cp437.py"
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

"$PYTHON_CHECK_BIN" - "$SITE" <<'PY'
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
"$PYTHON_CHECK_BIN" -m venv "$CHECK_VENV"
PIP_DISABLE_PIP_VERSION_CHECK=1 PIP_CACHE_DIR="$CHECK_VENV/pip-cache" PYTHONPATH="$SITE" \
  "$CHECK_VENV/bin/python" -m pip check >/dev/null
trap - EXIT
rm -rf "$CHECK_VENV"

PYTHONPATH="$SITE" HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 "$PYTHON_CHECK_BIN" - "$SITE" "$LOCK" <<'PY'
import importlib
import importlib.util
import codecs
from importlib import metadata
import os
from pathlib import Path
import re
import sys

from packaging.requirements import Requirement
from packaging.utils import canonicalize_name

site_root = str(Path(sys.argv[1]).resolve())
lock = Path(sys.argv[2])

modules = [
    "docling_bridge.converter",
    "docling_bridge.security",
    "upmarket_models.model_manager",
]

for module in modules:
    importlib.import_module(module)

codecs.lookup("cp437")

bundle_required_modules = [
    "docling.datamodel.vlm_model_specs",
    "docling.pipeline.vlm_pipeline",
    "mlx.core",
]

for module in bundle_required_modules:
    spec = importlib.util.find_spec(module)
    origin = getattr(spec, "origin", "") if spec else ""
    if not origin or not origin.startswith(site_root):
        raise SystemExit(f"error: bundled runtime module missing or outside app bundle: {module} origin={origin or 'missing'}")

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
