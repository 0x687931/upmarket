#!/usr/bin/env bash
# Make the Granite AI weights available to a locally-installed Upmarket without a download.
#
# Debug builds have no hosted model manifest, so the in-app "Download" can't run. The model
# directory only has to contain config.json + a *.safetensors shard to count as installed
# (ModelManager.modelDirectoryIsPopulated), so we just copy a local model dir into the app's
# sandbox Application Support and the app picks it up as downloaded on next launch.
#
# Get the weights first (one-time):
#   hf download ibm-granite/granite-docling-258M-mlx \
#     --revision e9939db25d2f296c8678d0491c4609a8c596c50a \
#     --local-dir "$HOME/Library/Application Support/Upmarket/models/upmarket_ai"
#
# Then: scripts/dev/stage_debug_model.sh   (optionally pass the source model dir as $1)
set -euo pipefail

KEY=upmarket_ai
BUNDLE_ID="${UPMARKET_BUNDLE_ID:-com.upmarket.app}"
SRC="${1:-$HOME/Library/Application Support/Upmarket/models/$KEY}"
CONTAINER="$HOME/Library/Containers/$BUNDLE_ID/Data/Library/Application Support/Upmarket/models"
DEST="$CONTAINER/$KEY"

if [[ ! -f "$SRC/config.json" ]]; then
  echo "error: no model at $SRC" >&2
  echo "  download it first (see the header of this script), or pass the model dir as the first argument." >&2
  exit 1
fi

mkdir -p "$DEST"
rsync -a --delete --exclude '.cache' --exclude '.git*' --exclude 'README.md' "$SRC"/ "$DEST"/
echo "staged $KEY → $DEST"
ls "$DEST"
echo "relaunch Upmarket; the AI model now shows as installed (set the tier to Max in Debug → Tier Override to use it)."
