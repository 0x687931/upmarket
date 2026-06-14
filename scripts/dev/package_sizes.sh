#!/usr/bin/env bash
# Report ACTUAL bundled Python package sizes — per top-level package, sorted largest
# first, with the tier each package belongs to (basic/pro/ai per requirements-*.txt).
#
# Usage:
#   scripts/dev/package_sizes.sh                 # the bundled (basic) runtime
#   scripts/dev/package_sizes.sh <site-packages> # any site-packages dir
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

DEFAULT_SITE="Upmarket/Python/Python.xcframework/macos-arm64_x86_64/Python.framework/Versions/3.12/lib/python3.12/site-packages"
SITE="${1:-$DEFAULT_SITE}"
FW_ROOT="$(dirname "$(dirname "$(dirname "$SITE")")")"   # .../Versions/3.12

if [[ ! -d "$SITE" ]]; then
  echo "error: site-packages not found: $SITE" >&2
  echo "       (run scripts/ci/ensure_python_runtime.sh to build the bundled runtime)" >&2
  exit 1
fi

# Map a site-packages directory name -> tier by scanning the requirements files.
# Imperfect (dir names differ from pip names, e.g. PIL/Pillow) but covers the pins.
tier_of() {
  local name; name="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  for tier in basic pro ai; do
    if grep -qiE "^${name}==|^${name//_/-}==|^${name//-/_}==" "requirements-${tier}.txt" 2>/dev/null; then
      printf '%s' "$tier"; return
    fi
  done
  printf 'dep'   # transitive dependency (pulled in, not directly pinned)
}

printf '%-34s %8s  %s\n' "PACKAGE" "SIZE" "TIER"
printf '%-34s %8s  %s\n' "----------------------------------" "--------" "----"

# du each top-level entry, sort by size desc, annotate with tier.
# shellcheck disable=SC2012
du -sk "$SITE"/* 2>/dev/null | sort -rn | while read -r kb path; do
  base="$(basename "$path")"
  [[ "$base" == *.dist-info || "$base" == __pycache__ ]] && continue
  human="$(awk -v k="$kb" 'BEGIN{ if(k>=1048576) printf "%.1fG", k/1048576; else if(k>=1024) printf "%.1fM", k/1024; else printf "%dK", k }')"
  printf '%-34s %8s  %s\n' "$base" "$human" "$(tier_of "$base")"
done

echo "------------------------------------------------------------"
printf '%-34s %8s\n' "site-packages total" "$(du -sh "$SITE" | cut -f1)"
printf '%-34s %8s\n' "stdlib + interpreter"  "$(du -sh "$FW_ROOT" 2>/dev/null | cut -f1)"
echo
echo "Legend: basic/pro/ai = directly pinned in requirements-<tier>.txt; dep = transitive."
echo "Note: the app bundles ONLY the basic tier; pro/ai install as downloads."
