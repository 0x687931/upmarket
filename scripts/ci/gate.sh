#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

MODE="${1:-quick}"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-build/DerivedData}"
RESULT_BUNDLE_DIR="${UPMARKET_RESULT_BUNDLE_DIR:-build/TestResults}"
PROJECT="${UPMARKET_XCODE_PROJECT:-Upmarket/Upmarket.xcodeproj}"
SCHEME="${UPMARKET_XCODE_SCHEME:-Upmarket}"
DESTINATION="${UPMARKET_XCODE_DESTINATION:-platform=macOS,arch=arm64}"
CODE_SIGNING="${UPMARKET_CODE_SIGNING_ALLOWED:-NO}"
UI_CODE_SIGN_IDENTITY="${UPMARKET_UI_CODE_SIGN_IDENTITY:--}"

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
  UPMARKET_RESULT_BUNDLE_DIR       Defaults to build/TestResults for UI test .xcresult bundles.
  UPMARKET_CODE_SIGNING_ALLOWED    Defaults to NO for local/CI testing.
  UPMARKET_UI_CODE_SIGN_IDENTITY   Defaults to - for post-build ad-hoc UI test signing.
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

# Swift macro fingerprint validation is bypassed because the bundled UpmarketVLM package
# depends on mlx-swift-lm's MLXHuggingFaceMacros, which can't be interactively trusted in CI.
xcode_build() {
  xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -skipMacroValidation \
    CODE_SIGNING_ALLOWED="$CODE_SIGNING"
}

xcode_unit_tests() {
  xcodebuild test \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -only-testing:UpmarketTests \
    -skipMacroValidation \
    CODE_SIGNING_ALLOWED="$CODE_SIGNING"
}

xcode_ui_tests() {
  local result_bundle
  result_bundle="${UPMARKET_UI_RESULT_BUNDLE_PATH:-$RESULT_BUNDLE_DIR/UpmarketUITests-${GITHUB_RUN_ID:-local}-$(date +%Y%m%d%H%M%S).xcresult}"
  mkdir -p "$(dirname "$result_bundle")"

  xcodebuild build-for-testing \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -only-testing:UpmarketUITests \
    -skipMacroValidation \
    CODE_SIGNING_ALLOWED="$CODE_SIGNING"

  local products_dir="$DERIVED_DATA_DIR/Build/Products"
  local app="$products_dir/Debug/Upmarket.app"
  local runner="$products_dir/Debug/UpmarketUITests-Runner.app"
  if [[ -d "$app" ]]; then
    codesign --force --deep --sign "$UI_CODE_SIGN_IDENTITY" "$app"
  fi
  if [[ -d "$runner" ]]; then
    codesign --force --deep --sign "$UI_CODE_SIGN_IDENTITY" "$runner"
  fi

  local xctestrun
  xctestrun="$(find "$products_dir" -name "*.xctestrun" -print | sort | tail -n 1)"
  if [[ -z "$xctestrun" ]]; then
    echo "error: unable to find .xctestrun under $products_dir"
    exit 1
  fi

  xcodebuild test-without-building \
    -xctestrun "$xctestrun" \
    -destination "$DESTINATION" \
    -resultBundlePath "$result_bundle" \
    -parallel-testing-enabled NO \
    -only-testing:UpmarketUITests
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
  run_step "Verify source entitlements" scripts/ci/verify_entitlements.sh
}

build_gate() {
  run_step "Build unsigned app" xcode_build
  run_step "Verify effective plist" scripts/ci/verify_effective_plist.sh
  run_step "Validate MCP server smoke" scripts/ci/validate_mcp_server.py "$DERIVED_DATA_DIR/Build/Products/Debug/Upmarket.app"
}

unit_gate() {
  run_step "Unit tests" xcode_unit_tests
}

# Conversion is native-only; there is no embedded Python runtime to build or verify, so
# "runtime" mode now rebuilds and verifies the packaged app (entitlements, no-Python embed,
# bundled CLI/MCP). Use it for entitlement, model, corpus, or packaging changes.
runtime_gate() {
  build_gate
  run_step "Verify built app package gates" scripts/ci/verify_release_app.sh "$DERIVED_DATA_DIR/Build/Products/Debug/Upmarket.app"
}

corpus_and_model_gate() {
  run_step "Validate corpus manifest" scripts/ci/validate_corpus.py
  run_step "Validate corpus baseline" scripts/ci/validate_corpus_baseline.py
  run_step "Validate corpus conversion pathways" scripts/ci/validate_corpus_pathways.py
  hf_dataset_gate
}

hf_dataset_gate() {
  # HuggingFace datasets are optional — skip gracefully if not downloaded
  if [ ! -d "tests/datasets/huggingface/pdfa-eng-wds" ]; then
    echo "⚠️  HuggingFace datasets not downloaded — skipping (run scripts/datasets/download_hf_datasets.sh)"
    return 0
  fi
  run_step "Benchmark HuggingFace datasets" bash scripts/datasets/benchmark_hf.sh --dataset all --fail-below 75
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
