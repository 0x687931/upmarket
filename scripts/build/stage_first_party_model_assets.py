#!/usr/bin/env python3
"""Stage validated model files and first-party manifests for Apple-hosted downloads."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import shutil
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
MODEL_MANAGER = REPO_ROOT / "UpmarketPython" / "models" / "model_manager.py"


def load_model_manager():
    spec = importlib.util.spec_from_file_location("upmarket_model_manager_assets", MODEL_MANAGER)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load {MODEL_MANAGER}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_relative(path: str) -> bool:
    return bool(path) and not path.startswith("/") and ".." not in Path(path).parts


def collect_files(model_path: Path, expected_files: list[str], expected_dirs: list[str]) -> list[str]:
    files = list(expected_files)
    for directory in expected_dirs:
        root = model_path / directory
        files.extend(
            str(path.relative_to(model_path))
            for path in sorted(root.rglob("*"))
            if path.is_file()
        )
    unique = sorted(dict.fromkeys(files))
    unsafe = [path for path in unique if not safe_relative(path)]
    if unsafe:
        raise RuntimeError(f"unsafe model paths: {', '.join(unsafe)}")
    return unique


def stage_model(manager, model_key: str, output_dir: Path) -> None:
    info = manager.MODELS[model_key]
    source_id = info.get("source_id")
    if not source_id:
        raise RuntimeError(f"{model_key} is missing source_id")

    model_path = manager.model_directory(model_key)
    valid, reason = manager.validate_model_dir(model_key, model_path)
    if not valid:
        raise RuntimeError(f"{model_key} is not validated: {reason}")

    storage_dir = info.get("storage_dir", model_key)
    model_output_dir = output_dir / model_key
    if model_output_dir.exists():
        shutil.rmtree(model_output_dir)
    model_output_dir.mkdir(parents=True)

    entries = []
    for relative in collect_files(model_path, info["expected_files"], info.get("expected_dirs", [])):
        source = model_path / relative
        destination = model_output_dir / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        entries.append(
            {
                "path": relative,
                "url": f"{model_key}/{relative}",
                "sha256": sha256(source),
                "bytes": source.stat().st_size,
            }
        )

    manifest = {
        "manifest_version": manager.MANIFEST_VERSION,
        "model_key": model_key,
        "source_id": source_id,
        "revision": info["revision"],
        "storage_dir": storage_dir,
        "expected_files": info["expected_files"],
        "expected_dirs": info.get("expected_dirs", []),
        "files": entries,
    }
    manifest_path = output_dir / f"{model_key}.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"staged {model_key}: {len(entries)} files, manifest {manifest_path}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Create first-party model manifests and file trees for upload to the "
            "Apple-hosted Upmarket model download location."
        )
    )
    parser.add_argument("--output", default="build/first-party-model-assets")
    parser.add_argument(
        "--model",
        action="append",
        dest="models",
        help="Model key to stage. Repeatable. Defaults to all configured models.",
    )
    args = parser.parse_args()

    manager = load_model_manager()
    model_keys = args.models or sorted(manager.MODELS)
    unknown = sorted(set(model_keys) - set(manager.MODELS))
    if unknown:
        print(f"error: unknown model(s): {', '.join(unknown)}", file=sys.stderr)
        return 2

    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    try:
        for model_key in model_keys:
            stage_model(manager, model_key, output_dir)
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    print(f"ok: upload contents of {output_dir} to the configured Apple-hosted model base URL")
    return 0


if __name__ == "__main__":
    os.chdir(REPO_ROOT)
    sys.exit(main())
