#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path


def main() -> int:
    models_dir = Path(os.environ.get(
        "UPMARKET_MODELS_DIR",
        Path.home() / "Library" / "Application Support" / "Upmarket" / "models",
    ))

    if not models_dir.exists():
        print("ok: no local models installed")
        return 0

    failed = False
    for model_dir in sorted(p for p in models_dir.iterdir() if p.is_dir()):
        files = [p for p in model_dir.rglob("*") if p.is_file()]
        if not files:
            continue

        manifest = model_dir / "upmarket_manifest.json"
        if not manifest.exists():
            print(f"error: model directory has files but no validation manifest: {model_dir}")
            failed = True
            continue

        try:
            data = json.loads(manifest.read_text())
        except Exception as exc:
            print(f"error: invalid model manifest {manifest}: {exc}")
            failed = True
            continue

        for key in ("repo_id", "revision", "validated_at", "files"):
            if key not in data:
                print(f"error: model manifest missing '{key}': {manifest}")
                failed = True

    if failed:
        return 1

    print("ok: model directories are empty or manifest-validated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
