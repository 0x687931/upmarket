#!/bin/bash
# Validate or install exact-pinned Python dependency states.
#
# Usage:
#   ./scripts/update_dependencies.sh --check-only
#   ./scripts/update_dependencies.sh --install-current
#   ./scripts/update_dependencies.sh --install-candidate
#
# This script never resolves "latest" versions and never writes dependency
# lock files. Put proposed pins in requirements-candidate.txt, validate them,
# then promote through review by copying exact pins to requirements.txt.

set -euo pipefail

MODE="${1:---check-only}"
CURRENT_LOCK="requirements.txt"
CANDIDATE_LOCK="requirements-candidate.txt"
VENV=".venv"
SITE="Upmarket/Python/Python.xcframework/macos-arm64_x86_64/Python.framework/Versions/3.12/lib/python3.12/site-packages"

case "$MODE" in
  --check-only|--install-current|--install-candidate) ;;
  *)
    echo "error: unknown mode: $MODE"
    echo "usage: $0 [--check-only|--install-current|--install-candidate]"
    exit 2
    ;;
esac

if [[ ! -x "$VENV/bin/pip" ]]; then
  echo "error: missing virtualenv pip at $VENV/bin/pip"
  echo "run: python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"
  exit 1
fi

echo "==> Validating dependency locks"
scripts/ci/validate_dependency_lock.py --current "$CURRENT_LOCK" --candidate "$CANDIDATE_LOCK"
echo ""

echo "==> Current release pins"
"$VENV/bin/pip" show docling markitdown pypdfium2 torch transformers huggingface-hub mlx mlx-metal mlx-vlm 2>/dev/null \
  | grep -E "^Name:|^Version:" | paste - - | column -t || true
echo ""

echo "==> Checking installed environment consistency"
"$VENV/bin/pip" check
"$VENV/bin/python" scripts/ci/validate_installed_pins.py --requirements "$CURRENT_LOCK"
echo ""

echo "==> Reporting upstream drift without promotion"
scripts/ci/watch_upstream.py --requirements "$CURRENT_LOCK" --candidate-requirements "$CANDIDATE_LOCK"
echo ""

if [[ "$MODE" == "--check-only" ]]; then
  echo "==> Check-only mode: no packages installed, no lock files changed."
  exit 0
fi

LOCK="$CURRENT_LOCK"
if [[ "$MODE" == "--install-candidate" ]]; then
  LOCK="$CANDIDATE_LOCK"
fi

echo "==> Installing exact pins from $LOCK into $VENV"
"$VENV/bin/pip" install --requirement "$LOCK"
echo ""

echo "==> Checking installed environment consistency after install"
"$VENV/bin/pip" check
"$VENV/bin/python" scripts/ci/validate_installed_pins.py --requirements "$LOCK"
echo ""

echo "==> Re-applying MPS compatibility patch"
./scripts/patch_mps.sh "$VENV"
echo ""

if [[ -d "$SITE" ]]; then
  echo "==> Syncing first-party bridge files into bundled framework"
  scripts/ci/sync_python_bridge.sh "$SITE"
  ./scripts/patch_mps.sh "$SITE"
  scripts/ci/verify_python_bundle.sh
else
  echo "warning: bundled site-packages not found at $SITE; skipped bundle sync"
fi

echo ""
echo "==> Done. Run dependency audit, packaged import/offline smoke, and corpus validation before promotion."
