#!/bin/bash
# Download diverse OCR test corpus with ground truth
# Sources: FUNSD, CORD, Corpus-Correctum, Kitab, OCR Bio Testfiles, Evans-TCP

set -eu

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CORPUS_DIR="$REPO_ROOT/tests/corpus_test"
mkdir -p "$CORPUS_DIR"

echo "📚 Setting up diverse OCR test corpus"
echo "===================================="
echo ""

# 1. FUNSD (forms with OCR)
echo "📋 Downloading FUNSD (forms, ~150 MB)..."
cd "$CORPUS_DIR"
if [ ! -d "FUNSD" ]; then
    git clone https://github.com/jinhyuk-lee/funsd.git FUNSD 2>&1 | grep -E "(Cloning|done)" || true
    echo "   ✓ FUNSD"
fi

# 2. CORD (receipts with OCR)
echo "📄 Downloading CORD (receipts, ~600 MB)..."
if [ ! -d "CORD" ]; then
    git clone https://github.com/AnyiBi/CORD.git CORD 2>&1 | grep -E "(Cloning|done)" || true
    echo "   ✓ CORD"
fi

# 3. Corpus-Correctum (Latin OCR correction)
echo "🏛️  Downloading Corpus-Correctum (Latin, ~50 MB)..."
if [ ! -d "Corpus-Correctum" ]; then
    git clone https://github.com/Mythologos/Corpus-Correctum.git Corpus-Correctum 2>&1 | grep -E "(Cloning|done)" || true
    echo "   ✓ Corpus-Correctum"
fi

# 4. Kitab Project (Arabic OCR)
echo "🕌 Downloading Kitab Project (Arabic)..."
if [ ! -d "kitab" ]; then
    git clone https://github.com/kitab-project/corpus.git kitab 2>&1 | grep -E "(Cloning|done)" || true
    echo "   ✓ Kitab Project"
fi

# 5. OCR English Biology Testfiles
echo "🔬 Downloading OCR Bio Testfiles..."
if [ ! -d "ocr-eng-bio-testfiles" ]; then
    git clone https://github.com/wollmers/ocr-eng-bio-testfiles.git 2>&1 | grep -E "(Cloning|done)" || true
    echo "   ✓ OCR Bio Testfiles"
fi

# 6. Evans-TCP (historical texts)
echo "📜 Downloading Evans-TCP (historical)..."
if [ ! -d "historical-texts" ]; then
    git clone https://github.com/Anterotesis/historical-texts.git 2>&1 | grep -E "(Cloning|done)" || true
    echo "   ✓ Evans-TCP"
fi

cd "$REPO_ROOT"

echo ""
echo "✅ Corpus setup complete"
echo ""
echo "Location: $CORPUS_DIR"
echo ""
echo "Datasets:"
echo "  • FUNSD - form documents with OCR (150 MB)"
echo "  • CORD - receipts with bounding boxes (600 MB)"
echo "  • Corpus-Correctum - Latin texts with OCR correction (50 MB)"
echo "  • Kitab - Arabic documents with OCR (variable)"
echo "  • OCR Bio Testfiles - scientific OCR test data"
echo "  • Evans-TCP - historical documents with transcriptions"
echo ""
echo "Total expected: ~1-2 GB"
