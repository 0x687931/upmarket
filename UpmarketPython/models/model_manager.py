"""
Manages ML model presence and download for Upmarket.
Models are cached in ~/Library/Application Support/Upmarket/models/
After download, HF_HUB_OFFLINE=1 prevents any further hub calls.
"""

import os
import json
from pathlib import Path

MODELS_DIR = Path(os.environ.get("HF_HUB_CACHE", Path.home() / "Library" / "Application Support" / "Upmarket" / "models"))

MODELS = {
    "layout": {
        "name": "Upmarket",
        "description": "Document understanding, tables, and layout detection",
        "repo_id": "ds4sd/docling-models",
        "size_mb": 400,
        "required": True,
        "tier": "basic",
    },
    "upmarket_ai": {
        "name": "Upmarket AI",
        "description": "Advanced understanding for complex and scanned documents",
        "repo_id": "docling-project/SmolDocling-256M-preview-mlx-bf16-docling-snap",
        "size_mb": 500,
        "required": False,
        "tier": "pro",
    },
}


def check_models() -> dict:
    """
    Returns status of each model.
    { model_key: { name, description, downloaded, size_mb, required, tier } }
    """
    status = {}
    for key, info in MODELS.items():
        model_path = MODELS_DIR / key
        downloaded = model_path.exists() and any(model_path.iterdir()) if model_path.exists() else False
        status[key] = {
            "name": info["name"],
            "description": info["description"],
            "downloaded": downloaded,
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
    dest.mkdir(parents=True, exist_ok=True)

    def write_progress(percent: float, message: str):
        if progress_file:
            with open(progress_file, "a") as f:
                f.write(json.dumps({"percent": percent, "message": message}) + "\n")

    try:
        from huggingface_hub import snapshot_download
        from huggingface_hub import hf_hub_download

        write_progress(0.0, f"Starting download of {info['name']}…")

        snapshot_download(
            repo_id=info["repo_id"],
            local_dir=str(dest),
            local_dir_use_symlinks=False,
        )

        write_progress(100.0, f"{info['name']} ready")
        return {"success": True, "error": None}

    except Exception as e:
        return {"success": False, "error": str(e)}


def set_offline_mode():
    """Call after all required models are downloaded."""
    os.environ["HF_HUB_OFFLINE"] = "1"


def all_required_downloaded() -> bool:
    status = check_models()
    return all(v["downloaded"] for v in status.values() if v["required"])


def required_download_size_mb() -> int:
    return sum(info["size_mb"] for info in MODELS.values() if info["required"])


def pro_download_size_mb() -> int:
    return sum(info["size_mb"] for info in MODELS.values() if info["tier"] == "pro")
