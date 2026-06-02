#!/usr/bin/env python3
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
MODEL_MANAGER = REPO_ROOT / "UpmarketPython" / "models" / "model_manager.py"
VALIDATE_MODELS = REPO_ROOT / "scripts" / "ci" / "validate_models.py"


def load_model_manager(models_dir: Path):
    os.environ["UPMARKET_MODELS_DIR"] = str(models_dir)
    spec = importlib.util.spec_from_file_location("upmarket_model_manager_faults", MODEL_MANAGER)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load {MODEL_MANAGER}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def assert_invalid(manager, key: str, path: Path, expected: str) -> None:
    valid, reason = manager.validate_model_dir(key, path)
    if valid:
        raise AssertionError(f"{path} unexpectedly validated")
    if expected not in (reason or ""):
        raise AssertionError(f"expected '{expected}' in validation reason, got '{reason}'")


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="upmarket-model-faults-") as temp:
        root = Path(temp)
        manager = load_model_manager(root)
        layout = root / "layout"
        layout.mkdir()

        (layout / "config.json").write_text("{}", encoding="utf-8")
        assert_invalid(manager, "layout", layout, "model_artifacts")

        artifacts = layout / "model_artifacts"
        artifacts.mkdir()
        (artifacts / "placeholder").write_text("partial", encoding="utf-8")
        assert_invalid(manager, "layout", layout, "manifest")

        manifest = {
            "manifest_version": manager.MANIFEST_VERSION,
            "model_key": "layout",
            "repo_id": manager.MODELS["layout"]["repo_id"],
            "revision": manager.MODELS["layout"]["revision"],
            "expected_files": manager.MODELS["layout"]["expected_files"],
            "expected_dirs": manager.MODELS["layout"]["expected_dirs"],
            "files": {"config.json": "0" * 64},
            "validated_at": "2026-06-01T00:00:00+00:00",
        }
        (layout / manager.MANIFEST_NAME).write_text(json.dumps(manifest), encoding="utf-8")
        assert_invalid(manager, "layout", layout, "checksum mismatch")

        staging = root / ".layout.download"
        staging.mkdir()
        result = subprocess.run(
            [sys.executable, str(VALIDATE_MODELS)],
            cwd=REPO_ROOT,
            env={**os.environ, "UPMARKET_MODELS_DIR": str(root)},
            text=True,
            capture_output=True,
            check=False,
        )
        if result.returncode == 0 or "incomplete staging model directory" not in result.stdout:
            raise AssertionError(
                "validate_models.py did not reject incomplete staging directory\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )

        staging.rmdir()
        shutil.rmtree(layout)

        pro_key = "upmarket_ai"
        pro_info = manager.MODELS[pro_key]
        pro_dir = root / pro_info["storage_dir"]
        pro_dir.mkdir()
        file_hashes = {}
        for relative in pro_info["expected_files"]:
            path = pro_dir / relative
            path.write_text(relative, encoding="utf-8")
            file_hashes[relative] = manager._sha256(path)
        manifest = {
            "manifest_version": manager.MANIFEST_VERSION,
            "model_key": pro_key,
            "repo_id": pro_info["repo_id"],
            "revision": pro_info["revision"],
            "expected_files": pro_info["expected_files"],
            "expected_dirs": pro_info["expected_dirs"],
            "files": file_hashes,
            "validated_at": "2026-06-01T00:00:00+00:00",
        }
        (pro_dir / manager.MANIFEST_NAME).write_text(json.dumps(manifest), encoding="utf-8")

        result = subprocess.run(
            [sys.executable, str(VALIDATE_MODELS)],
            cwd=REPO_ROOT,
            env={**os.environ, "UPMARKET_MODELS_DIR": str(root)},
            text=True,
            capture_output=True,
            check=False,
        )
        if result.returncode != 0:
            raise AssertionError(
                "validate_models.py rejected configured Pro storage directory\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )

        unexpected = root / "unexpected-model"
        unexpected.mkdir()
        result = subprocess.run(
            [sys.executable, str(VALIDATE_MODELS)],
            cwd=REPO_ROOT,
            env={**os.environ, "UPMARKET_MODELS_DIR": str(root)},
            text=True,
            capture_output=True,
            check=False,
        )
        if result.returncode == 0 or "unexpected model directory" not in result.stdout:
            raise AssertionError(
                "validate_models.py did not reject unexpected model directory\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )

    print("ok: model fault tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
