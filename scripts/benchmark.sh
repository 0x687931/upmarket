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
#   ./scripts/benchmark.sh --fail-below 85        # fail if score < 85%
#   ./scripts/benchmark.sh --json-output reports/corpus-fast.json
#   ./scripts/benchmark.sh --compare fast enhanced # diff two pipelines

set -euo pipefail

CORPUS_DIR="tests/corpus"
VENV=".venv"
FAIL_BELOW=0
PIPELINE=""
PATHWAY=""
CATEGORY=""
COMPARE_MODE=false
JSON_OUTPUT=""
REPEAT=1
COMPUTE_MODE="auto"

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --pipeline) PIPELINE="$2"; shift 2 ;;
        --pathway) PATHWAY="$2"; shift 2 ;;
        --category) CATEGORY="$2"; shift 2 ;;
        --fail-below) FAIL_BELOW="$2"; shift 2 ;;
        --json-output) JSON_OUTPUT="$2"; shift 2 ;;
        --repeat) REPEAT="$2"; shift 2 ;;
        --compute-mode) COMPUTE_MODE="$2"; shift 2 ;;
        --compare) PIPELINE="$2"; COMPARE_PIPELINE="$3"; COMPARE_MODE=true; shift 3 ;;
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
echo "  Repeat: $REPEAT"
echo "  Compute Mode: $COMPUTE_MODE"
echo "═══════════════════════════════════════════════"
echo ""

# Run Python benchmark scorer
PYTHON="$VENV/bin/python3"
if [ ! -x "$PYTHON" ]; then
    PYTHON="python3"
fi

"$PYTHON" scripts/benchmark_scorer.py \
    --corpus "$CORPUS_DIR" \
    ${PIPELINE:+--pipeline "$PIPELINE"} \
    ${PATHWAY:+--pathway "$PATHWAY"} \
    ${CATEGORY:+--category "$CATEGORY"} \
    ${JSON_OUTPUT:+--json-output "$JSON_OUTPUT"} \
    --repeat "$REPEAT" \
    --compute-mode "$COMPUTE_MODE" \
    --fail-below "$FAIL_BELOW"
