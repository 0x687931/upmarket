#!/usr/bin/env python3
import argparse
import json
import os
import sys
import importlib.util
from datetime import datetime, timezone
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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate Upmarket model cache manifests.")
    parser.add_argument(
        "--repair",
        action="store_true",
        help="Repair pinned legacy manifests or quarantine unusable local model directories.",
    )
    return parser.parse_args()


def quarantine_model_dir(model_dir: Path, models_dir: Path, reason: str) -> tuple[bool, str]:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    quarantine_base = Path(os.environ.get("UPMARKET_MODEL_QUARANTINE_DIR", models_dir.parent / "InvalidModels"))
    quarantine_root = quarantine_base / stamp
    quarantine_root.mkdir(parents=True, exist_ok=True)

    destination = quarantine_root / model_dir.name
    suffix = 1
    while destination.exists():
        destination = quarantine_root / f"{model_dir.name}-{suffix}"
        suffix += 1

    try:
        model_dir.replace(destination)
    except Exception as exc:
        return False, f"error: unable to quarantine invalid model directory {model_dir}: {exc}"

    return True, (
        f"repair: quarantined invalid model directory {model_dir.name}: {reason}. "
        "Download it again from Upmarket Settings."
    )


def fail_or_quarantine(model_dir: Path, models_dir: Path, reason: str, repair: bool) -> bool:
    if not repair:
        print(f"error: {reason}: {model_dir}")
        return True

    ok, message = quarantine_model_dir(model_dir, models_dir, reason)
    print(message)
    return not ok


def main() -> int:
    args = parse_args()
    models_dir = Path(os.environ.get(
        "UPMARKET_MODELS_DIR",
        Path.home() / "Library" / "Application Support" / "Upmarket" / "models",
    ))
    manager = load_model_manager()

    if not models_dir.exists():
        print("ok: no local models installed")
        return 0

    storage_to_key = {
        info.get("storage_dir", key): key
        for key, info in manager.MODELS.items()
    }

    failed = False
    for model_dir in sorted(p for p in models_dir.iterdir() if p.is_dir()):
        if model_dir.name.startswith("."):
            failed = fail_or_quarantine(
                model_dir,
                models_dir,
                "incomplete staging model directory present",
                args.repair,
            ) or failed
            continue

        model_key = storage_to_key.get(model_dir.name)
        if model_key is None:
            failed = fail_or_quarantine(
                model_dir,
                models_dir,
                "unexpected model directory",
                args.repair,
            ) or failed
            continue

        files = [p for p in model_dir.rglob("*") if p.is_file()]
        if not files:
            continue

        manifest = model_dir / manager.MANIFEST_NAME
        if not manifest.exists():
            if not args.repair:
                failed = fail_or_quarantine(
                    model_dir,
                    models_dir,
                    "model directory has files but no validation manifest",
                    repair=False,
                ) or failed
            else:
                repaired, reason = manager.repair_missing_manifest(model_key, model_dir)
                if repaired:
                    print(f"repair: wrote validation manifest for {model_dir.name}")
                else:
                    failed = fail_or_quarantine(
                        model_dir,
                        models_dir,
                        f"model directory has files but no validation manifest ({reason})",
                        repair=True,
                    ) or failed
            continue

        manifest_error = None
        try:
            data = json.loads(manifest.read_text())
        except Exception as exc:
            manifest_error = f"invalid model manifest {manifest}: {exc}"
            data = {}

        for key in ("repo_id", "revision", "validated_at", "files"):
            if key not in data:
                manifest_error = manifest_error or f"model manifest missing '{key}': {manifest}"

        valid, reason = manager.validate_model_dir(model_key, model_dir)
        if manifest_error or not valid:
            reason = manifest_error or f"model validation failed for {model_dir.name}: {reason}"
            failed = fail_or_quarantine(model_dir, models_dir, reason, args.repair) or failed

    if failed:
        return 1

    print("ok: model directories are empty or manifest-validated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
