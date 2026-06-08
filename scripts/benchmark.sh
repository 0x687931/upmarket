#!/bin/bash
# benchmark.sh
# Runs Upmarket conversion quality benchmarks against the test corpus.
# Scores each document against its ground truth (.expected.md).
#
# Usage:
#   ./scripts/benchmark.sh                        # full run
#   ./scripts/benchmark.sh --pipeline fast        # specific pipeline
#   ./scripts/benchmark.sh --pathway python-fast-pdfium
#   ./scripts/benchmark.sh --repeat 3       # average wall-time across runs
#   ./scripts/benchmark.sh --compute-mode cpu|gpu|ane|auto
#   ./scripts/benchmark.sh --category pdf_digital # specific category
#   ./scripts/benchmark.sh --bucket digital-complex # native|digital-complex|scanned-or-unknown
#   ./scripts/benchmark.sh --fail-below 85        # fail if score < 85%
#   ./scripts/benchmark.sh --json-output reports/corpus-fast.json
#   ./scripts/benchmark.sh --compare fast enhanced # diff two pipelines
#
# Multi-pathway quality mode (mirrors ConversionRunner quality selection):
#   ./scripts/benchmark.sh --quality                        # pro_ai tier (all pathways)
#   ./scripts/benchmark.sh --quality --tier basic           # PDFKit + Vision only
#   ./scripts/benchmark.sh --quality --bucket scanned-or-unknown
#   ./scripts/benchmark.sh --quality --doc docling_test_01
#   ./scripts/benchmark.sh --quality --json-output reports/quality.json

set -euo pipefail

CORPUS_DIR="tests/corpus"
VENV=".venv"
FAIL_BELOW=0
PIPELINE=""
PATHWAY=""
CATEGORY=""
BUCKET=""
COMPARE_MODE=false
QUALITY_MODE=false
QUALITY_TIER="pro_ai"
QUALITY_DOC=""
JSON_OUTPUT=""
REPEAT=1
COMPUTE_MODE="auto"

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --pipeline) PIPELINE="$2"; shift 2 ;;
        --pathway) PATHWAY="$2"; shift 2 ;;
        --category) CATEGORY="$2"; shift 2 ;;
        --bucket) BUCKET="$2"; shift 2 ;;
        --fail-below) FAIL_BELOW="$2"; shift 2 ;;
        --json-output) JSON_OUTPUT="$2"; shift 2 ;;
        --repeat) REPEAT="$2"; shift 2 ;;
        --compute-mode) COMPUTE_MODE="$2"; shift 2 ;;
        --compare) PIPELINE="$2"; COMPARE_PIPELINE="$3"; COMPARE_MODE=true; shift 3 ;;
        --quality) QUALITY_MODE=true; shift ;;
        --tier) QUALITY_TIER="$2"; shift 2 ;;
        --doc) QUALITY_DOC="$2"; shift 2 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

if [ ! -d "$CORPUS_DIR" ]; then
    echo "Corpus not found at $CORPUS_DIR"
    echo "Run: git clone https://github.com/0x687931/upmarket-corpus tests/corpus"
    exit 1
fi

echo "═══════════════════════════════════════════════"
echo "  Upmarket Benchmark"
echo "  Corpus: $CORPUS_DIR"
[ -n "$PIPELINE" ] && echo "  Pipeline: $PIPELINE"
[ -n "$PATHWAY" ] && echo "  Pathway: $PATHWAY"
[ -n "$CATEGORY" ] && echo "  Category: $CATEGORY"
[ -n "$BUCKET" ] && echo "  Bucket: $BUCKET"
echo "  Repeat: $REPEAT"
echo "  Compute Mode: $COMPUTE_MODE"
echo "═══════════════════════════════════════════════"
echo ""

scripts/ci/sync_python_bridge.sh >/dev/null

# Run Python benchmark scorer
PYTHON="$VENV/bin/python3"
if [ ! -x "$PYTHON" ]; then
    PYTHON="python3"
fi

# Validate AI model is present before running an AI pipeline benchmark.
# The converter's input-workspace guard also requires UPMARKET_ALLOWED_INPUT_ROOTS;
# set it to the resolved corpus directory so corpus files pass the security check.
if [ -n "$PIPELINE" ] && [ "$PIPELINE" = "ai" ]; then
    if ! "$PYTHON" -c "
import sys; sys.path.insert(0, 'UpmarketPython')
from models.model_manager import validate_model_dir
ok, err = validate_model_dir('upmarket_ai')
if not ok:
    print(f'ERROR: Upmarket AI model is missing or invalid: {err}')
    print('Download the model from Settings > Models before running the AI benchmark.')
    sys.exit(1)
" 2>&1; then
        exit 1
    fi
    echo "  AI model: ready"
    echo ""
fi

CORPUS_ABS="$(cd "$CORPUS_DIR" && pwd)"
export UPMARKET_ALLOWED_INPUT_ROOTS="$CORPUS_ABS"
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1
# Point scorer at the installed model directory so its setdefault() does not
# redirect to the benchmark cache, which is empty for user-installed models.
export UPMARKET_MODELS_DIR="${HOME}/Library/Application Support/Upmarket/models"

# Multi-pathway quality mode — mirrors ConversionRunner's quality selection
if [ "$QUALITY_MODE" = true ]; then
    if [ "$QUALITY_TIER" = "pro_ai" ]; then
        if ! "$PYTHON" -c "
import sys; sys.path.insert(0, 'UpmarketPython')
from models.model_manager import validate_model_dir
ok, err = validate_model_dir('upmarket_ai')
if not ok:
    print(f'ERROR: AI model missing — use --tier basic or download from Settings > Models.')
    sys.exit(1)
" 2>&1; then
            exit 1
        fi
        echo "  AI model: ready"
        echo ""
    fi
    "$PYTHON" scripts/benchmark_quality.py \
        --corpus "$CORPUS_DIR" \
        --tier "$QUALITY_TIER" \
        ${BUCKET:+--bucket "$BUCKET"} \
        ${QUALITY_DOC:+--doc "$QUALITY_DOC"} \
        ${JSON_OUTPUT:+--json-output "$JSON_OUTPUT"}
    exit $?
fi

"$PYTHON" scripts/benchmark_scorer.py \
    --corpus "$CORPUS_DIR" \
    ${PIPELINE:+--pipeline "$PIPELINE"} \
    ${PATHWAY:+--pathway "$PATHWAY"} \
    ${CATEGORY:+--category "$CATEGORY"} \
    ${BUCKET:+--bucket "$BUCKET"} \
    ${JSON_OUTPUT:+--json-output "$JSON_OUTPUT"} \
    --repeat "$REPEAT" \
    --compute-mode "$COMPUTE_MODE" \
    --fail-below "$FAIL_BELOW"
