#!/usr/bin/env bash
set -euo pipefail

# Stage the source Python runtime where the runtime helper resolves it, for LOCAL DEV only.
#
# The app no longer embeds a Python runtime (Basic is native; Python is a Pro download).
# In production the helper resolves the framework from the downloaded Background Asset at
#   ~/Library/Application Support/Upmarket/runtime/python_runtime/Python.framework
# (see UpmarketRuntimeHelper resolveFrameworkRoot). For local Pro testing this symlinks the
# repo's source xcframework into that path so the helper can launch and import Python.
#
# Notes:
#   - This stages the BASIC runtime (markitdown/pypdfium2/etc.). Docling/MLX (Pro/Max) are
#     NOT included — build those with scripts/build_python_tiers.sh if you need them.
#   - It refuses to overwrite a real downloaded runtime; use --force to replace a symlink
#     this script created, or --unstage to remove it.
#   - The debug helper is unsandboxed, so it reads the real ~/Library/Application Support.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_FRAMEWORK="$ROOT/Upmarket/Python/Python.xcframework/macos-arm64_x86_64/Python.framework"
RUNTIME_DIR="$HOME/Library/Application Support/Upmarket/runtime/python_runtime"
TARGET="$RUNTIME_DIR/Python.framework"

ACTION="stage"
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --unstage) ACTION="unstage" ;;
    --force) FORCE=1 ;;
    -h|--help) sed -n '3,17p' "$0"; exit 0 ;;
    *) echo "error: unknown argument: $arg" >&2; exit 2 ;;
  esac
done

if [[ "$ACTION" == "unstage" ]]; then
  if [[ -L "$TARGET" ]]; then
    rm "$TARGET"
    echo "ok: removed dev runtime symlink: $TARGET"
  elif [[ -e "$TARGET" ]]; then
    echo "error: $TARGET is not a symlink this script created — leaving it untouched." >&2
    exit 1
  else
    echo "ok: nothing staged."
  fi
  exit 0
fi

if [[ ! -d "$SOURCE_FRAMEWORK" ]]; then
  echo "error: source runtime missing: $SOURCE_FRAMEWORK" >&2
  echo "       Run scripts/ci/ensure_python_runtime.sh (or scripts/build_python_env.sh)." >&2
  exit 1
fi

if [[ -e "$TARGET" || -L "$TARGET" ]]; then
  if [[ -L "$TARGET" && "$FORCE" == "1" ]]; then
    rm "$TARGET"
  elif [[ -L "$TARGET" ]]; then
    echo "ok: dev runtime already staged at $TARGET (use --force to repoint, --unstage to remove)."
    exit 0
  else
    echo "error: $TARGET already exists and is NOT a symlink (a real downloaded runtime?)." >&2
    echo "       Refusing to overwrite. Remove it yourself if you intend to stage the dev runtime." >&2
    exit 1
  fi
fi

mkdir -p "$RUNTIME_DIR"
ln -s "$SOURCE_FRAMEWORK" "$TARGET"
echo "ok: staged dev Python runtime"
echo "    $TARGET -> $SOURCE_FRAMEWORK"
echo "    (Basic runtime only; build the Pro tier for Docling — scripts/build_python_tiers.sh)"
