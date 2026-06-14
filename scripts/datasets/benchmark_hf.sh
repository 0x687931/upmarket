#!/bin/bash
# Benchmark HuggingFace datasets against thresholds
# Usage: bash scripts/datasets/benchmark_hf.sh [--dataset pdfa|idl|docvqa|all] [--fail-below 75]

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
DATASETS=("pdfa" "idl" "docvqa")
FAIL_THRESHOLD=75

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dataset)
            if [[ $2 == "all" ]]; then
                DATASETS=("pdfa" "idl" "docvqa")
            else
                DATASETS=("$2")
            fi
            shift 2
            ;;
        --fail-below)
            FAIL_THRESHOLD=$2
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "📊 HuggingFace Dataset Benchmark"
echo "================================"
echo "Datasets: ${DATASETS[*]}"
echo "Fail threshold: ${FAIL_THRESHOLD}%"
echo ""

OVERALL_PASS=true

for dataset in "${DATASETS[@]}"; do
    echo "⏱️  ${dataset}..."

    case $dataset in
        pdfa)
            python3 "$SCRIPT_DIR/datasets/evaluate_pdfa.py" || OVERALL_PASS=false
            ;;
        idl)
            python3 "$SCRIPT_DIR/datasets/evaluate_idl.py" || OVERALL_PASS=false
            ;;
        docvqa)
            python3 "$SCRIPT_DIR/datasets/evaluate_docvqa.py" || OVERALL_PASS=false
            ;;
    esac

    echo ""
done

if [ "$OVERALL_PASS" = true ]; then
    echo "✅ All benchmarks passed"
    exit 0
else
    echo "❌ One or more benchmarks failed"
    exit 1
fi
