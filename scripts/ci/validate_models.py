#!/usr/bin/env python3
import json
import os
import sys
import importlib.util
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
MODEL_MANAGER = REPO_ROOT / "UpmarketPython" / "models" / "model_manager.py"


def load_model_manager():
    spec = importlib.util.spec_from_file_location("upmarket_model_manager", MODEL_MANAGER)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load {MODEL_MANAGER}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    models_dir = Path(os.environ.get(
        "UPMARKET_MODELS_DIR",
        Path.home() / "Library" / "Application Support" / "Upmarket" / "models",
    ))
    manager = load_model_manager()

    if not models_dir.exists():
        print("ok: no local models installed")
        return 0

    failed = False
    for model_dir in sorted(p for p in models_dir.iterdir() if p.is_dir()):
        if model_dir.name.startswith("."):
            print(f"error: incomplete staging model directory present: {model_dir}")
            failed = True
            continue

        if model_dir.name not in manager.MODELS:
            print(f"error: unexpected model directory: {model_dir}")
            failed = True
            continue

        files = [p for p in model_dir.rglob("*") if p.is_file()]
        if not files:
            continue

        manifest = model_dir / manager.MANIFEST_NAME
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

        valid, reason = manager.validate_model_dir(model_dir.name, model_dir)
        if not valid:
            print(f"error: model validation failed for {model_dir.name}: {reason}")
            failed = True

    if failed:
        return 1

    print("ok: model directories are empty or manifest-validated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
