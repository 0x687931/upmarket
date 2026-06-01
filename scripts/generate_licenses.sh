#!/bin/bash
# generate_licenses.sh
# Auto-generates the open source license list used in the About screen.
# Run before each release or when dependencies change.
# Output: Upmarket/Upmarket/Resources/licenses.json
#
# Usage: ./scripts/generate_licenses.sh

set -euo pipefail

VENV=".venv"
OUT="Upmarket/Upmarket/Resources/licenses.json"
mkdir -p "$(dirname "$OUT")"

echo "==> Generating license list..."

$VENV/bin/pip install pip-licenses -q

# Generate JSON with only packages we actually ship or use
$VENV/bin/pip-licenses \
    --format=json \
    --with-urls \
    --packages \
        pdfplumber \
        pdfminer.six \
        markitdown \
        pypdfium2 \
        docling \
        docling-core \
        docling-parse \
        docling-ibm-models \
        torch \
        torchvision \
        transformers \
        huggingface-hub \
        pillow \
        pydantic \
        numpy \
    2>/dev/null | python3 -c "
import sys, json

pkgs = json.load(sys.stdin)
out = []
for p in sorted(pkgs, key=lambda x: x['Name'].lower()):
    out.append({
        'name': p['Name'],
        'version': p['Version'],
        'license': p['License'],
        'url': p.get('URL', '')
    })

# Add manually managed entries not in pip
out.extend([
    {'name': 'BeeWare Python-Apple-support', 'version': '3.12-b8', 'license': 'MIT',
     'url': 'https://github.com/beeware/Python-Apple-support'},
    {'name': 'PythonKit', 'version': '0.5.1', 'license': 'Apache-2.0',
     'url': 'https://github.com/pvieito/PythonKit'},
])
out.sort(key=lambda x: x['name'].lower())

print(json.dumps(out, indent=2))
" > "$OUT"

COUNT=$(python3 -c "import json; print(len(json.load(open('$OUT'))))")
echo "==> Generated $COUNT license entries → $OUT"
