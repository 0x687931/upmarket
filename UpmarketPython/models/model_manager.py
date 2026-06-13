"""
Manages ML model presence and download for Upmarket.
Models are cached in ~/Library/Application Support/Upmarket/models/
After download, HF_HUB_OFFLINE=1 prevents any further hub calls.
"""

import hashlib
import json
import os
import platform
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

RUNTIME_DIR = Path(
    os.environ.get("UPMARKET_RUNTIME_DIR")
    or Path.home() / "Library" / "Application Support" / "Upmarket" / "runtime"
)

MODELS = {
    "python_runtime": {
        "name": "Upmarket Runtime",
        "description": "Required for Enhanced and AI conversion on Apple Silicon",
        "source_id": "com.upmarket.runtime.python",
        "repo_id": None,   # not a HF Hub model — downloaded via CDN manifest
        "revision": "1",
        "storage_dir": "python_runtime",
        "expected_files": ["upmarket_runtime_ready"],
        "expected_dirs": ["Python.framework"],
        "size_mb": 1300,
        "required": False,
        "tier": "pro",
    },
    "layout": {
        "name": "Upmarket Enhanced",
        "description": "Better results for complex PDFs, tables, and multi-column documents",
        "source_id": "com.upmarket.models.layout",
        "repo_id": "ds4sd/docling-models",
        "revision": "72661864b9c29fb7cced011822786bed346811ea",
        "expected_files": ["config.json"],
        "expected_dirs": ["model_artifacts"],
        "size_mb": 172,
        "required": False,   # not required — fast path works without it
        "tier": "pro",       # same as python_runtime — both required for Enhanced conversion
    },
    "upmarket_ai": {
        "name": "Upmarket AI",
        "description": "Best results for scanned, handwritten, and research documents",
        "source_id": "com.upmarket.models.upmarket-ai",
        "repo_id": "ibm-granite/granite-docling-258M-mlx",
        "revision": "e9939db25d2f296c8678d0491c4609a8c596c50a",
        "storage_dir": "ibm-granite--granite-docling-258M-mlx",
        "expected_files": [
            "config.json",
            "model.safetensors",
            "preprocessor_config.json",
            "processor_config.json",
            "tokenizer.json",
        ],
        "expected_dirs": [],
        "size_mb": 631,
        "required": False,
        "tier": "max",
    },
}


def _manifest_path(model_path: Path) -> Path:
    return model_path / MANIFEST_NAME


def model_directory(model_key: str) -> Path:
    if model_key not in MODELS:
        raise KeyError(f"unknown model: {model_key}")
    if model_key == "python_runtime":
        return RUNTIME_DIR / "python_runtime"
    return MODELS_DIR / MODELS[model_key].get("storage_dir", model_key)


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


def downloaded_revision(model_key: str, model_path: Path | None = None) -> str | None:
    """Best-effort revision recorded by Hugging Face local_dir metadata."""
    if model_key not in MODELS:
        return None

    info = MODELS[model_key]
    model_path = model_path or model_directory(model_key)
    metadata_root = model_path / ".cache" / "huggingface" / "download"

    for relative in info["expected_files"]:
        metadata = metadata_root / f"{relative}.metadata"
        if not metadata.is_file():
            continue
        try:
            revision = metadata.read_text().splitlines()[0].strip()
        except Exception:
            continue
        if revision:
            return revision

    refs = model_path / f"models--{info['repo_id'].replace('/', '--')}" / "refs"
    if refs.is_dir():
        for ref in sorted(refs.iterdir()):
            if not ref.is_file():
                continue
            try:
                revision = ref.read_text().strip()
            except Exception:
                continue
            if revision:
                return revision

    return None


def validate_model_dir(model_key: str, model_path: Path | None = None) -> tuple[bool, str | None]:
    """Return whether a model directory is complete, pinned, and manifest-validated."""
    if model_key not in MODELS:
        return False, f"unknown model: {model_key}"

    info = MODELS[model_key]
    model_path = model_path or model_directory(model_key)
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
        "revision": info["revision"],
    }
    if info.get("repo_id"):
        expected["repo_id"] = info["repo_id"]
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


def repair_missing_manifest(model_key: str, model_path: Path | None = None) -> tuple[bool, str | None]:
    """Write a manifest for a legacy cache only when its recorded revision is pinned."""
    if model_key not in MODELS:
        return False, f"unknown model: {model_key}"

    info = MODELS[model_key]
    model_path = model_path or model_directory(model_key)
    if not model_path.exists():
        return False, "not downloaded"
    if _manifest_path(model_path).exists():
        return False, "validation manifest already exists"

    ok, error = _validate_expected_paths(model_path, info)
    if not ok:
        return False, error

    revision = downloaded_revision(model_key, model_path)
    if revision != info["revision"]:
        found = revision or "unknown"
        return False, f"downloaded revision mismatch: expected {info['revision']}, found {found}"

    _write_manifest(model_key, model_path)
    return validate_model_dir(model_key, model_path)


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
        "revision": info["revision"],
        "expected_files": info["expected_files"],
        "expected_dirs": info.get("expected_dirs", []),
        "files": files,
        "validated_at": datetime.now(timezone.utc).isoformat(),
    }
    if info.get("repo_id"):
        manifest["repo_id"] = info["repo_id"]
    manifest_path = _manifest_path(model_path)
    temp_path = manifest_path.with_name(f".{manifest_path.name}.tmp")
    temp_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    temp_path.replace(manifest_path)


def _download_allow_patterns(info: dict) -> list[str]:
    patterns = list(info["expected_files"])
    for relative in info.get("expected_dirs", []):
        patterns.append(f"{relative}/**")
    return patterns


def check_models() -> dict:
    """
    Returns status of each model.
    { model_key: { name, description, downloaded, size_mb, required, tier } }
    """
    status = {}
    for key, info in MODELS.items():
        model_path = model_directory(key)
        downloaded, error = validate_model_dir(key, model_path)
        unavailable = None
        if key == "python_runtime" and not supports_upmarket_ai_hardware():
            unavailable = "Enhanced conversion requires Apple Silicon."
        if key == "upmarket_ai" and not supports_upmarket_ai_hardware():
            unavailable = "Upmarket AI requires Apple Silicon with Metal support."
        status[key] = {
            "name": info["name"],
            "description": info["description"],
            "downloaded": downloaded,
            "error": None if downloaded else unavailable or error,
            "size_mb": info["size_mb"],
            "required": info["required"],
            "tier": info["tier"],
            "available": unavailable is None,
            "storage_dir": info.get("storage_dir", key),
        }
    return status


def supports_upmarket_ai_hardware() -> bool:
    """Granite Docling MLX is an Apple Silicon/Metal path, not a generic GPU path."""
    return platform.system() == "Darwin" and platform.machine() == "arm64"


def download_model(model_key: str, progress_file: str | None = None) -> dict:
    """
    Download a model by key.
    Writes progress to progress_file as JSON lines: {"percent": float, "message": str}
    Returns { "success": bool, "error": str | None }
    """
    if model_key not in MODELS:
        return {"success": False, "error": f"Unknown model: {model_key}"}
    if model_key == "python_runtime":
        # Runtime is downloaded by the Swift layer via Apple CDN manifest, not HF Hub.
        return {"success": False, "error": "python_runtime cannot be downloaded via this path."}
    if model_key == "upmarket_ai" and not supports_upmarket_ai_hardware():
        return {"success": False, "error": "Upmarket AI requires Apple Silicon with Metal support."}

    info = MODELS[model_key]
    dest = model_directory(model_key)
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
            allow_patterns=_download_allow_patterns(info),
            max_workers=4,
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

        write_progress(98.0, f"{info['name']} ready")

        # Download the figure classifier alongside the layout model — it's
        # 16MB MIT-licensed and enables DocumentFigureClassifier in the
        # Enhanced pipeline for better chart/photo/diagram handling.
        if model_key == "layout" and not figure_classifier_available():
            try:
                download_figure_classifier()
            except Exception:
                pass  # Non-fatal — Enhanced pipeline works without it

        write_progress(100.0, f"{info['name']} ready")
        return {"success": True, "error": None}

    except Exception as e:
        if staging.exists():
            shutil.rmtree(staging, ignore_errors=True)
        return {"success": False, "error": str(e)}


_FIGURE_CLASSIFIER_REPO = "docling-project/DocumentFigureClassifier-v2.5"
_FIGURE_CLASSIFIER_REVISION = "main"
_FIGURE_CLASSIFIER_FILES = ["config.json", "model.safetensors", "preprocessor_config.json"]


def figure_classifier_available() -> bool:
    """True when DocumentFigureClassifier weights are in the HuggingFace hub cache."""
    cache_dir = Path(os.environ.get("HF_HOME", Path.home() / ".cache" / "huggingface")) / "hub"
    repo_dir = cache_dir / _FIGURE_CLASSIFIER_REPO.replace("/", "--").replace("/", "--")
    # HF stores as models--org--repo
    hf_cache_name = "models--" + _FIGURE_CLASSIFIER_REPO.replace("/", "--")
    return (cache_dir / hf_cache_name).exists()


def download_figure_classifier(write_progress=None) -> dict:
    """Download DocumentFigureClassifier-v2.5 (16MB, MIT) into the HF hub cache.

    This is a companion to the Enhanced (layout) model. It enables figure type
    classification (chart, photograph, diagram, etc.) inside the Enhanced pipeline
    without any additional user-visible model setup.
    """
    def _progress(pct, msg):
        if write_progress:
            write_progress(pct, msg)

    try:
        from huggingface_hub import snapshot_download
        _progress(10.0, "Downloading figure classifier…")
        snapshot_download(
            repo_id=_FIGURE_CLASSIFIER_REPO,
            revision=_FIGURE_CLASSIFIER_REVISION,
            allow_patterns=["*.json", "*.safetensors"],
        )
        _progress(100.0, "Figure classifier ready")
        return {"success": True, "error": None}
    except Exception as e:
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


def max_download_size_mb() -> int:
    return sum(info["size_mb"] for info in MODELS.values() if info["tier"] == "max")
