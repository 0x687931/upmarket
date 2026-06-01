"""
Manages ML model presence and download for Upmarket.
Models are cached in ~/Library/Application Support/Upmarket/models/
After download, HF_HUB_OFFLINE=1 prevents any further hub calls.
"""

import hashlib
import json
import os
import shutil
from datetime import datetime, timezone
from pathlib import Path

MODELS_DIR = Path(
    os.environ.get("UPMARKET_MODELS_DIR")
    or os.environ.get("HF_HUB_CACHE")
    or Path.home() / "Library" / "Application Support" / "Upmarket" / "models"
)
MANIFEST_NAME = "upmarket_manifest.json"
MANIFEST_VERSION = 1

MODELS = {
    "layout": {
        "name": "Upmarket Enhanced",
        "description": "Better results for complex PDFs, tables, and multi-column documents",
        "repo_id": "ds4sd/docling-models",
        "revision": "72661864b9c29fb7cced011822786bed346811ea",
        "expected_files": ["config.json"],
        "expected_dirs": ["model_artifacts"],
        "size_mb": 172,
        "required": False,   # not required — fast path works without it
        "tier": "enhanced",
    },
    "upmarket_ai": {
        "name": "Upmarket AI",
        "description": "Best results for scanned, handwritten, and research documents",
        "repo_id": "docling-project/SmolDocling-256M-preview-mlx-bf16-docling-snap",
        "revision": "54a18c06969c29e2f9b01532337327c54c2b8933",
        "expected_files": [
            "config.json",
            "model.safetensors",
            "preprocessor_config.json",
            "processor_config.json",
            "tokenizer.json",
        ],
        "expected_dirs": [],
        "size_mb": 500,
        "required": False,
        "tier": "pro",
    },
}


def _manifest_path(model_path: Path) -> Path:
    return model_path / MANIFEST_NAME


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _read_manifest(model_path: Path) -> dict | None:
    manifest = _manifest_path(model_path)
    if not manifest.exists():
        return None
    try:
        return json.loads(manifest.read_text())
    except Exception:
        return None


def _validate_expected_paths(model_path: Path, info: dict) -> tuple[bool, str | None]:
    for relative in info["expected_files"]:
        candidate = model_path / relative
        if not candidate.is_file():
            return False, f"missing expected model file: {relative}"

    for relative in info.get("expected_dirs", []):
        candidate = model_path / relative
        if not candidate.is_dir() or not any(candidate.iterdir()):
            return False, f"missing expected model directory: {relative}"

    return True, None


def validate_model_dir(model_key: str, model_path: Path | None = None) -> tuple[bool, str | None]:
    """Return whether a model directory is complete, pinned, and manifest-validated."""
    if model_key not in MODELS:
        return False, f"unknown model: {model_key}"

    info = MODELS[model_key]
    model_path = model_path or MODELS_DIR / model_key
    if not model_path.exists():
        return False, "not downloaded"
    if not model_path.is_dir():
        return False, "model path is not a directory"

    ok, error = _validate_expected_paths(model_path, info)
    if not ok:
        return False, error

    manifest = _read_manifest(model_path)
    if not manifest:
        return False, "missing or invalid validation manifest"

    expected = {
        "manifest_version": MANIFEST_VERSION,
        "model_key": model_key,
        "repo_id": info["repo_id"],
        "revision": info["revision"],
    }
    for field, value in expected.items():
        if manifest.get(field) != value:
            return False, f"manifest {field} mismatch"

    files = manifest.get("files")
    if not isinstance(files, dict):
        return False, "manifest missing file checksums"

    for relative in info["expected_files"]:
        candidate = model_path / relative
        expected_hash = files.get(relative)
        if not expected_hash:
            return False, f"manifest missing checksum for {relative}"
        if _sha256(candidate) != expected_hash:
            return False, f"checksum mismatch for {relative}"

    return True, None


def model_available(model_key: str) -> bool:
    valid, _ = validate_model_dir(model_key)
    return valid


def _write_manifest(model_key: str, model_path: Path) -> None:
    info = MODELS[model_key]
    files = {
        relative: _sha256(model_path / relative)
        for relative in info["expected_files"]
    }
    manifest = {
        "manifest_version": MANIFEST_VERSION,
        "model_key": model_key,
        "repo_id": info["repo_id"],
        "revision": info["revision"],
        "expected_files": info["expected_files"],
        "expected_dirs": info.get("expected_dirs", []),
        "files": files,
        "validated_at": datetime.now(timezone.utc).isoformat(),
    }
    _manifest_path(model_path).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")


def check_models() -> dict:
    """
    Returns status of each model.
    { model_key: { name, description, downloaded, size_mb, required, tier } }
    """
    status = {}
    for key, info in MODELS.items():
        model_path = MODELS_DIR / key
        downloaded, error = validate_model_dir(key, model_path)
        status[key] = {
            "name": info["name"],
            "description": info["description"],
            "downloaded": downloaded,
            "error": None if downloaded else error,
            "size_mb": info["size_mb"],
            "required": info["required"],
            "tier": info["tier"],
        }
    return status


def download_model(model_key: str, progress_file: str | None = None) -> dict:
    """
    Download a model by key.
    Writes progress to progress_file as JSON lines: {"percent": float, "message": str}
    Returns { "success": bool, "error": str | None }
    """
    if model_key not in MODELS:
        return {"success": False, "error": f"Unknown model: {model_key}"}

    info = MODELS[model_key]
    dest = MODELS_DIR / model_key
    staging = MODELS_DIR / f".{model_key}.download"
    MODELS_DIR.mkdir(parents=True, exist_ok=True)

    def write_progress(percent: float, message: str):
        if progress_file:
            with open(progress_file, "a") as f:
                f.write(json.dumps({"percent": percent, "message": message}) + "\n")

    try:
        from huggingface_hub import snapshot_download

        if staging.exists():
            shutil.rmtree(staging)
        staging.mkdir(parents=True)

        write_progress(0.0, f"Starting download of {info['name']}…")

        snapshot_download(
            repo_id=info["repo_id"],
            revision=info["revision"],
            local_dir=str(staging),
            local_dir_use_symlinks=False,
        )

        write_progress(90.0, "Validating model files…")
        ok, error = _validate_expected_paths(staging, info)
        if not ok:
            raise RuntimeError(error)

        _write_manifest(model_key, staging)
        ok, error = validate_model_dir(model_key, staging)
        if not ok:
            raise RuntimeError(error)

        if dest.exists():
            shutil.rmtree(dest)
        staging.rename(dest)

        write_progress(100.0, f"{info['name']} ready")
        return {"success": True, "error": None}

    except Exception as e:
        if staging.exists():
            shutil.rmtree(staging, ignore_errors=True)
        return {"success": False, "error": str(e)}


def set_offline_mode():
    """Call after all required models are downloaded."""
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"


def all_required_downloaded() -> bool:
    status = check_models()
    return all(v["downloaded"] for v in status.values() if v["required"])


def required_download_size_mb() -> int:
    return sum(info["size_mb"] for info in MODELS.values() if info["required"])


def pro_download_size_mb() -> int:
    return sum(info["size_mb"] for info in MODELS.values() if info["tier"] == "pro")
