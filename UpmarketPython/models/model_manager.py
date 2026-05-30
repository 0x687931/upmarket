"""
Manages ML model presence and download for Upmarket.
Models are cached in ~/Library/Application Support/Upmarket/models/
After download, HF_HUB_OFFLINE=1 prevents any further hub calls.
"""

import os
import json
from pathlib import Path


MODELS_DIR = Path.home() / "Library" / "Application Support" / "Upmarket" / "models"

MODELS = {
    "layout": {
        "name": "Heron Layout (RT-DETRv2)",
        "repo_id": "docling-project/docling-models",
        "size_mb": 300,
        "required": True,
    },
    "tableformer": {
        "name": "TableFormer",
        "repo_id": "docling-project/docling-models",
        "size_mb": 100,
        "required": True,
    },
    "smoldocling": {
        "name": "SmolDocling VLM",
        "repo_id": "docling-project/SmolDocling-256M-preview-mlx-bf16-docling-snap",
        "size_mb": 500,
        "required": False,
    },
}


def check_models() -> dict:
    """
    Returns status of each model.
    { model_key: { "name": str, "downloaded": bool, "size_mb": int, "required": bool } }
    """
    status = {}
    for key, info in MODELS.items():
        model_path = MODELS_DIR / key
        status[key] = {
            "name": info["name"],
            "downloaded": model_path.exists() and any(model_path.iterdir()),
            "size_mb": info["size_mb"],
            "required": info["required"],
        }
    return status


def download_model(model_key: str, progress_callback=None) -> dict:
    """
    Download a model by key. Calls progress_callback(percent: float, message: str).
    Returns { "success": bool, "error": str | None }
    """
    if model_key not in MODELS:
        return {"success": False, "error": f"Unknown model: {model_key}"}

    info = MODELS[model_key]
    dest = MODELS_DIR / model_key
    dest.mkdir(parents=True, exist_ok=True)

    try:
        from huggingface_hub import snapshot_download

        def hf_progress(progress):
            if progress_callback and hasattr(progress, "downloaded_size"):
                pct = min(99.0, (progress.downloaded_size / (info["size_mb"] * 1024 * 1024)) * 100)
                progress_callback(pct, f"Downloading {info['name']}...")

        snapshot_download(
            repo_id=info["repo_id"],
            local_dir=str(dest),
            ignore_patterns=["*.pt", "*.bin"] if model_key == "smoldocling" else [],
        )

        if progress_callback:
            progress_callback(100.0, f"{info['name']} ready")

        return {"success": True, "error": None}

    except Exception as e:
        return {"success": False, "error": str(e)}


def set_offline_mode():
    """Call after all required models are downloaded."""
    os.environ["HF_HUB_OFFLINE"] = "1"


def all_required_downloaded() -> bool:
    status = check_models()
    return all(v["downloaded"] for v in status.values() if v["required"])
