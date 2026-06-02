#!/usr/bin/env bash
set -euo pipefail

APP="${1:?usage: scripts/ci/verify_release_app.sh /path/to/Upmarket.app}"
SITE="$APP/Contents/Frameworks/Python.framework/Versions/3.12/lib/python3.12/site-packages"

if [[ ! -d "$APP" ]]; then
  echo "error: app bundle missing: $APP"
  exit 1
fi

scripts/ci/verify_effective_plist.sh "$APP"
scripts/ci/verify_entitlements.sh "$APP"
scripts/ci/verify_python_bundle.sh "$SITE"
scripts/ci/validate_runtime_helper.py "$APP"
scripts/ci/smoke_convert_offline.sh "$APP"

echo "ok: release app package gates passed"
