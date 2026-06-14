#!/usr/bin/env bash
# Orderly (re)download of the Upmarket evaluation corpus into tests/corpus/sources/.
# Only document+ground-truth pairs are kept (build_corpus.py does the pairing).
#
#   scripts/eval/fetch_corpus.sh            # docling pairs only (small, fast)
#   scripts/eval/fetch_corpus.sh --with-pdfa  # also pull + sample pdfa PDFs (large; needs git-xet)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# Pinned for reproducibility — bump deliberately.
DOCLING_SHA="ef9bb95e1e8e95655c2a56edad953e282b6bd15d"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> Docling test data @ ${DOCLING_SHA:0:12} (sparse: tests/data only)"
git -C "$WORK" init -q
git -C "$WORK" remote add origin https://github.com/docling-project/docling.git
git -C "$WORK" config core.sparseCheckout true
echo "tests/data" > "$WORK/.git/info/sparse-checkout"
git -C "$WORK" fetch -q --depth 1 origin "$DOCLING_SHA"
git -C "$WORK" checkout -q FETCH_HEAD

PDFA_ARGS=()
if [[ "${1:-}" == "--with-pdfa" ]]; then
  echo "==> pdfa (HuggingFace pixparse/pdfa-eng-wds) — large download via git-xet"
  bash scripts/datasets/download_hf_datasets.sh
  python3 scripts/datasets/prepare_hf_corpus.py --dataset pdfa --sample 100 --seed 42
  PDFA_ARGS=(--pdfa-src "$ROOT/tests/datasets/pdfa-eng-wds-extracted")
fi

echo "==> Building paired corpus + manifest"
python3 scripts/eval/build_corpus.py --docling-src "$WORK/tests/data" "${PDFA_ARGS[@]}"
echo "==> Done. tests/corpus/sources/ + tests/corpus/manifest.json"
