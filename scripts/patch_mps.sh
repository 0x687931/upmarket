#!/bin/bash
# patch_mps.sh
# Patches transformers RT-DETRv2 to use float32 instead of float64.
# MPS (Metal) on Apple Silicon does not support float64 tensors.
# Must be run after pip install and after any transformers upgrade.
#
# Usage: ./scripts/patch_mps.sh [venv-path]

VENV="${1:-.venv}"
FILE="$VENV/lib/python3.12/site-packages/transformers/models/rt_detr_v2/modeling_rt_detr_v2.py"

if [ ! -f "$FILE" ]; then
    echo "Error: $FILE not found. Run from repo root with venv active."
    exit 1
fi

if grep -q "torch.float64" "$FILE"; then
    sed -i '' 's/dtype=torch\.float64/dtype=torch.float32/g' "$FILE"
    echo "Patched: $FILE"
else
    echo "Already patched: $FILE"
fi
