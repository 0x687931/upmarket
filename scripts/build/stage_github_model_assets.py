#!/usr/bin/env python3
"""
Create GitHub-Release-ready model archives and manifest files.

This script packages each model as a single .tar.gz archive suitable for
upload to a GitHub Release. Manifests reference each archive by absolute URL
and are written to resources/model-manifests/ for commit to the repo.

Usage — one-time setup:

  # 1. Stage archives and manifests for a release tag
  scripts/build/stage_github_model_assets.py \\
      --release-url https://github.com/OWNER/REPO/releases/download/models-v1 \\
      --output build/github-model-assets

  # 2. Upload archives to the GitHub Release (requires gh CLI)
  gh release upload models-v1 build/github-model-assets/archives/*.tar.gz

  # 3. Commit manifests to the repo
  cp build/github-model-assets/manifests/*.json resources/model-manifests/
  git add resources/model-manifests/
  git commit -m "Update GitHub CDN model manifests for models-v1"

  # 4. In Xcode scheme Launch action add env var:
  #    UPMARKET_MODEL_MANIFEST_BASE_URL =
  #      https://raw.githubusercontent.com/OWNER/REPO/main/resources/model-manifests/

Model sources
-------------
python_runtime:
  Sourced from the bundled xcframework at
  Upmarket/Python/Python.xcframework/macos-arm64_x86_64/Python.framework.
  The sentinel file (upmarket_runtime_ready) is created automatically.

layout / upmarket_ai:
  Sourced from resources/models/ in the repo (Git LFS).
  If the files are not yet present, run:
    scripts/ci/ensure_models.sh
  then commit the downloaded weights before running this script.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
MODEL_MANAGER = REPO_ROOT / "UpmarketPython" / "models" / "model_manager.py"
BUNDLED_FRAMEWORK = (
    REPO_ROOT
    / "Upmarket"
    / "Python"
    / "Python.xcframework"
    / "macos-arm64_x86_64"
    / "Python.framework"
)


def load_model_manager():
    spec = importlib.util.spec_from_file_location("upmarket_model_manager_github", MODEL_MANAGER)
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


def create_archive(source_dir: Path, archive_path: Path) -> None:
    """Create a reproducible tar.gz of source_dir (contents, not the dir itself)."""
    archive_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["tar", "czf", str(archive_path), "-C", str(source_dir), "."],
        check=True,
        capture_output=True,
    )


def stage_python_runtime(manager, output_dir: Path, release_base_url: str) -> None:
    """
    Packages the bundled Python.framework plus the sentinel file.
    This does NOT require a prior developer-intake download.
    """
    if not BUNDLED_FRAMEWORK.exists():
        raise RuntimeError(
            f"Bundled Python.framework not found at {BUNDLED_FRAMEWORK}.\n"
            "Run scripts/ci/ensure_python_runtime.sh first."
        )

    model_key = "python_runtime"
    info = manager.MODELS[model_key]

    with tempfile.TemporaryDirectory() as tmp:
        staging = Path(tmp) / "python_runtime"
        staging.mkdir()

        # Copy the bundled Python.framework
        print(f"  Copying Python.framework (~1.3 GB, this takes a moment)…")
        subprocess.run(
            ["ditto", str(BUNDLED_FRAMEWORK), str(staging / "Python.framework")],
            check=True,
            capture_output=True,
        )

        # Create the sentinel file expected by isRuntimeInstalled()
        (staging / "upmarket_runtime_ready").touch()

        _stage_model_from_dir(manager, model_key, info, staging, output_dir, release_base_url)


def stage_downloaded_model(manager, model_key: str, output_dir: Path, release_base_url: str) -> None:
    """
    Stages a model from resources/models/ (Git LFS, preferred) or Application Support fallback.
    """
    repo_path = REPO_ROOT / "resources" / "models" / model_key
    app_support_path = manager.model_directory(model_key)

    if repo_path.exists():
        model_path = repo_path
    elif app_support_path.exists():
        print(f"  Warning: using Application Support copy of {model_key}. "
              f"Run scripts/ci/ensure_models.sh to populate resources/models/ instead.")
        model_path = app_support_path
    else:
        raise RuntimeError(
            f"{model_key} not found in resources/models/ or Application Support.\n"
            "Run: scripts/ci/ensure_models.sh"
        )

    valid, reason = manager.validate_model_dir(model_key, model_path)
    if not valid:
        raise RuntimeError(f"{model_key} failed validation: {reason}")

    info = manager.MODELS[model_key]
    _stage_model_from_dir(manager, model_key, info, model_path, output_dir, release_base_url)


def _stage_model_from_dir(
    manager,
    model_key: str,
    info: dict,
    source_dir: Path,
    output_dir: Path,
    release_base_url: str,
) -> None:
    archive_name = f"{model_key}.tar.gz"
    archives_dir = output_dir / "archives"
    archive_path = archives_dir / archive_name

    print(f"  Creating {archive_name}…")
    create_archive(source_dir, archive_path)

    archive_hash = sha256(archive_path)
    archive_bytes = archive_path.stat().st_size
    archive_url = f"{release_base_url.rstrip('/')}/{archive_name}"

    source_id = info.get("source_id")
    if not source_id:
        raise RuntimeError(f"{model_key} is missing source_id in MODELS dict")

    manifest = {
        "manifest_version": manager.MANIFEST_VERSION,
        "model_key": model_key,
        "source_id": source_id,
        "revision": info["revision"],
        "storage_dir": info.get("storage_dir", model_key),
        "expected_files": info["expected_files"],
        "expected_dirs": info.get("expected_dirs", []),
        "archive": {
            "url": archive_url,
            "sha256": archive_hash,
            "bytes": archive_bytes,
        },
        "files": [],
    }

    manifests_dir = output_dir / "manifests"
    manifests_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = manifests_dir / f"{model_key}.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")

    size_mb = archive_bytes / 1_048_576
    print(f"  {model_key}: {size_mb:.0f} MB → {archive_path.name}")
    print(f"    manifest: {manifest_path}")
    print(f"    sha256:   {archive_hash}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Stage GitHub-Release model archives and manifests for debug CDN.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--release-url",
        required=True,
        metavar="URL",
        help="GitHub Release download base URL, e.g. https://github.com/OWNER/REPO/releases/download/models-v1",
    )
    parser.add_argument(
        "--output",
        default="build/github-model-assets",
        metavar="DIR",
        help="Output directory (default: build/github-model-assets)",
    )
    parser.add_argument(
        "--model",
        action="append",
        dest="models",
        metavar="KEY",
        help="Model key to stage. Repeatable. Defaults to all configured models.",
    )
    args = parser.parse_args()

    manager = load_model_manager()
    model_keys = args.models or sorted(manager.MODELS)
    unknown = sorted(set(model_keys) - set(manager.MODELS))
    if unknown:
        print(f"error: unknown model(s): {', '.join(unknown)}", file=sys.stderr)
        return 2

    output_dir = REPO_ROOT / args.output
    output_dir.mkdir(parents=True, exist_ok=True)

    errors = []
    for key in model_keys:
        print(f"\n[{key}]")
        try:
            if key == "python_runtime":
                stage_python_runtime(manager, output_dir, args.release_url)
            else:
                stage_downloaded_model(manager, key, output_dir, args.release_url)
        except Exception as exc:
            print(f"  error: {exc}", file=sys.stderr)
            errors.append(key)

    archives_dir = output_dir / "archives"
    manifests_dir = output_dir / "manifests"

    print("\n" + "─" * 60)
    if errors:
        print(f"Staged with errors — skipped: {', '.join(errors)}")
    else:
        print("All models staged successfully.")

    if archives_dir.exists():
        print(f"\nNext steps:")
        print(f"  1. Upload archives to GitHub Release:")
        print(f"       gh release upload <tag> {archives_dir}/*.tar.gz")
        print(f"  2. Commit manifests to repo:")
        print(f"       cp {manifests_dir}/*.json resources/model-manifests/")
        print(f"       git add resources/model-manifests/ && git commit")
        print(f"  3. Set in Xcode scheme (Launch > Environment Variables):")
        release_url = args.release_url.rstrip("/")
        # Derive the raw.githubusercontent manifest URL by convention
        print(f"       UPMARKET_MODEL_MANIFEST_BASE_URL =")
        print(f"         https://raw.githubusercontent.com/OWNER/REPO/main/resources/model-manifests/")

    return 1 if errors else 0


if __name__ == "__main__":
    os.chdir(REPO_ROOT)
    sys.exit(main())
