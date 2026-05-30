#!/bin/bash
# benchmark.sh
# Runs Upmarket conversion quality benchmarks against the test corpus.
# Scores each document against its ground truth (.expected.md).
#
# Usage:
#   ./scripts/benchmark.sh                        # full run
#   ./scripts/benchmark.sh --pipeline fast        # specific pipeline
#   ./scripts/benchmark.sh --category pdf_digital # specific category
#   ./scripts/benchmark.sh --fail-below 85        # fail if score < 85%
#   ./scripts/benchmark.sh --compare fast enhanced # diff two pipelines

set -euo pipefail

CORPUS_DIR="tests/corpus"
VENV=".venv"
FAIL_BELOW=0
PIPELINE=""
CATEGORY=""
COMPARE_MODE=false

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --pipeline) PIPELINE="$2"; shift 2 ;;
        --category) CATEGORY="$2"; shift 2 ;;
        --fail-below) FAIL_BELOW="$2"; shift 2 ;;
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
[ -n "$CATEGORY" ] && echo "  Category: $CATEGORY"
echo "═══════════════════════════════════════════════"
echo ""

# Run Python benchmark scorer
$VENV/bin/python3 scripts/benchmark_scorer.py \
    --corpus "$CORPUS_DIR" \
    ${PIPELINE:+--pipeline "$PIPELINE"} \
    ${CATEGORY:+--category "$CATEGORY"} \
    --fail-below "$FAIL_BELOW"
