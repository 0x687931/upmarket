#!/bin/bash
# Download and set up HuggingFace datasets for validation
# Usage: bash scripts/datasets/download_hf_datasets.sh

set -eu

DATASETS_DIR="tests/datasets/huggingface"
DATASETS=(
    "pdfa-eng-wds"
    "idl-wds"
    "docvqa-wds"
    "docvqa-single-page-questions"
)

echo "📦 HuggingFace Dataset Download Setup"
echo "===================================="

# Check if git-xet is installed
if ! command -v git-xet &> /dev/null; then
    echo "📥 Installing git-xet via brew..."
    brew install git-xet
fi

# Initialize git-xet
echo "🔧 Initializing git-xet..."
git xet install

# Create datasets directory
mkdir -p "$DATASETS_DIR"
cd "$DATASETS_DIR"

# Clone each dataset repo
for dataset in "${DATASETS[@]}"; do
    if [ -d "$dataset/.git" ]; then
        echo "✓ $dataset already cloned, skipping"
    else
        echo "📥 Cloning $dataset..."
        git clone "https://huggingface.co/datasets/pixparse/$dataset" 2>&1 | grep -E "(Cloning|done)" || true
    fi
done

cd - > /dev/null

echo ""
echo "✅ HuggingFace datasets downloaded!"
echo ""
echo "Next step: prepare manifests by running:"
echo "  python3 scripts/datasets/prepare_hf_corpus.py --dataset all --sample 200 --seed 42"
