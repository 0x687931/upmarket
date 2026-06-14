#!/bin/bash
# Download HuggingFace datasets for validation
# Usage: bash scripts/datasets/download_hf_datasets.sh

set -eu

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DATASETS_DIR="$REPO_ROOT/tests/datasets/huggingface"
VENV_DIR="$REPO_ROOT/.venv"

echo "📦 HuggingFace Dataset Download Setup"
echo "===================================="

# Set up Python venv if needed
if [[ ! -d "$VENV_DIR" ]]; then
    echo "📦 Creating Python virtual environment..."
    python3 -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"
echo "✓ Virtual environment activated"

# Install dependencies
echo "📦 Installing dependencies..."
pip install -q webdataset pdfplumber huggingface-hub

# Install git-xet
if ! command -v git-xet &> /dev/null; then
    echo "📥 Installing git-xet..."
    brew install git-xet
fi

# Initialize git-xet
echo "🔧 Initializing git-xet..."
git xet install

# Create and enter datasets directory
mkdir -p "$DATASETS_DIR"
cd "$DATASETS_DIR"

# Clone datasets
echo ""
echo "📥 Cloning HuggingFace datasets..."
for dataset in pdfa-eng-wds idl-wds docvqa-wds docvqa-single-page-questions; do
    if [ -d "$dataset/.git" ]; then
        echo "  ✓ $dataset (already cloned)"
    else
        echo "  📥 $dataset (this may take a few minutes)..."
        git clone "https://huggingface.co/datasets/pixparse/$dataset" || echo "  ⚠️  Clone of $dataset had issues"
    fi
done

cd "$REPO_ROOT"

echo ""
echo "✅ Done! Datasets cloned to: $DATASETS_DIR"
echo ""
echo "Next: Prepare sample manifests:"
echo "  python3 scripts/datasets/prepare_hf_corpus.py --dataset all --sample 10"
