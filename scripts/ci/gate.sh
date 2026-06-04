#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

MODE="${1:-quick}"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-build/DerivedData}"
PROJECT="${UPMARKET_XCODE_PROJECT:-Upmarket/Upmarket.xcodeproj}"
SCHEME="${UPMARKET_XCODE_SCHEME:-Upmarket}"
DESTINATION="${UPMARKET_XCODE_DESTINATION:-platform=macOS,arch=arm64}"
CODE_SIGNING="${UPMARKET_CODE_SIGNING_ALLOWED:-NO}"
PYTHON_XCFRAMEWORK="${UPMARKET_PYTHON_XCFRAMEWORK:-Upmarket/Python/Python.xcframework}"

usage() {
  cat <<'USAGE'
usage: scripts/ci/gate.sh [policy|quick|runtime|release|minor|major|ui]

Gates:
  policy   Static policy checks only.
  quick    Normal local/PR gate: policy, unsigned build, plist, unit tests.
  runtime  Rebuild and verify bundled runtime, then verify the built app package.
  release  Minor release gate: policy, runtime package, app package, unit,
           corpus, and model checks.
  minor    Alias for release.
  major    Release gate plus UI automation.
  ui       UI automation only.

Environment:
  DERIVED_DATA_DIR                 Defaults to build/DerivedData.
  UPMARKET_CODE_SIGNING_ALLOWED    Defaults to NO for local/CI testing.
  UPMARKET_XCODE_DESTINATION       Defaults to platform=macOS,arch=arm64.
USAGE
}

section_start() {
  local title="$1"
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    printf '::group::%s\n' "$title"
  else
    printf '\n==> %s\n' "$title"
  fi
}

section_end() {
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    printf '::endgroup::\n'
  fi
}

run_step() {
  local title="$1"
  shift
  section_start "$title"
  "$@"
  section_end
}

xcode_build() {
  xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    CODE_SIGNING_ALLOWED="$CODE_SIGNING"
}

xcode_unit_tests() {
  xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -only-testing:UpmarketTests \
    CODE_SIGNING_ALLOWED="$CODE_SIGNING"
}

xcode_ui_tests() {
  xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -only-testing:UpmarketUITests \
    CODE_SIGNING_ALLOWED="$CODE_SIGNING"
}

require_build_runtime() {
  if [[ -d "$PYTHON_XCFRAMEWORK" ]]; then
    return 0
  fi

  echo "error: build runtime missing: $PYTHON_XCFRAMEWORK"
  echo "       Run scripts/ci/ensure_python_runtime.sh to prepare the local build runtime."
  exit 1
}

policy_gate() {
  run_step "Verify Xcode project" scripts/ci/verify_xcode_project.sh
  run_step "Validate P0 task registry" scripts/ci/validate_task_registry.py
  run_step "Validate P0 implementation plan sync" scripts/ci/validate_p0_plan_sync.py
  run_step "Validate architecture boundaries" scripts/ci/validate_architecture_boundaries.py
  run_step "Validate user-facing copy" scripts/ci/validate_user_facing_copy.py
  run_step "Validate Nova extension" scripts/ci/validate_nova_extension.py
  run_step "Validate generated repository docs" scripts/docs/generate_repo_docs.py --check
  run_step "Validate release regression guards" scripts/ci/validate_release_regression_guards.py
  run_step "Validate upstream watch workflow" scripts/ci/validate_upstream_watch_workflow.py
  run_step "Verify source entitlements" scripts/ci/verify_entitlements.sh
}

build_gate() {
  run_step "Check build runtime" require_build_runtime
  run_step "Build unsigned app" xcode_build
  run_step "Verify effective plist" scripts/ci/verify_effective_plist.sh
}

unit_gate() {
  run_step "Unit tests" xcode_unit_tests
}

runtime_gate() {
  run_step "Build Python runtime" scripts/build_python_env.sh
  run_step "Verify Python bundle imports" scripts/ci/verify_python_bundle.sh
  build_gate
  run_step "Verify built app package gates" scripts/ci/verify_release_app.sh "$DERIVED_DATA_DIR/Build/Products/Debug/Upmarket.app"
}

corpus_and_model_gate() {
  run_step "Validate corpus manifest" scripts/ci/validate_corpus.py
  run_step "Validate corpus baseline" scripts/ci/validate_corpus_baseline.py
  run_step "Validate corpus conversion pathways" scripts/ci/validate_corpus_pathways.py
  run_step "Repair and validate local model manifests" scripts/ci/validate_models.py --repair
  run_step "Validate model fault states" scripts/ci/test_model_faults.py
}

quick_gate() {
  policy_gate
  build_gate
  unit_gate
}

release_gate() {
  policy_gate
  runtime_gate
  unit_gate
  corpus_and_model_gate
}

case "$MODE" in
  policy)
    policy_gate
    ;;
  quick)
    quick_gate
    ;;
  runtime)
    runtime_gate
    ;;
  release|minor)
    release_gate
    ;;
  major)
    release_gate
    run_step "UI automation tests" xcode_ui_tests
    ;;
  ui)
    run_step "UI automation tests" xcode_ui_tests
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
