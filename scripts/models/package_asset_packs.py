#!/usr/bin/env python3
"""Package an Upmarket model as an Apple-hosted managed Background Assets pack (.aar).

Release/TestFlight delivers the Max-tier models as managed asset packs. Apple hosts and
distributes them; there are no CDN URLs in Swift. This tool stages a model's files under a
top-level directory named after the model key, validates the file set against the single
source of truth (stage_model_assets.MODELS — no second catalog), and runs `xcrun ba-package`.

    scripts/models/package_asset_packs.py --model granite_docling \
        --model-dir build/granite_docling \
        --out-dir build/asset-packs

The resulting .aar is uploaded to App Store Connect → Background Assets and associated with
the build. The `--selftest` flag runs an offline staging+validation check (skips ba-package).

Pack manifests live in resources/asset-packs/. The assetPackID in each manifest MUST match
the Swift mapping in ModelAsset.assetPackID.
"""
from __future__ import annotations
import argparse, json, shutil, subprocess, sys, tempfile
from pathlib import Path

# Single source of truth for expected files — reuse, do not duplicate.
from stage_model_assets import MODELS

REPO_ROOT = Path(__file__).resolve().parents[2]
MANIFESTS = REPO_ROOT / "resources" / "asset-packs"

# model key -> (manifest file, expected assetPackID). IDs must match the Swift mapping.
PACKS = {
    "granite_docling": ("granite.json", "com.upmarket.app.models.granite"),
    "lfm25_vl": ("lfm2.json", "com.upmarket.app.models.lfm25-vl"),
}


def stage(model_key: str, model_dir: Path, staging: Path) -> Path:
    """Copy expected files into <staging>/<model_key>/, failing on any missing file."""
    spec = MODELS[model_key]
    missing = [f for f in spec.expected_files if not (model_dir / f).is_file()]
    if missing:
        sys.exit(f"error: model-dir missing expected files: {', '.join(missing)}")
    dest = staging / model_key
    dest.mkdir(parents=True, exist_ok=True)
    for name in spec.expected_files:
        shutil.copy2(model_dir / name, dest / name)
    return dest


def manifest_for(model_key: str) -> Path:
    name, want_id = PACKS[model_key]
    path = MANIFESTS / name
    got_id = json.loads(path.read_text())["assetPackID"]
    if got_id != want_id:
        sys.exit(f"error: {name} assetPackID {got_id!r} != expected {want_id!r}")
    # The directory selector must match the staged top-level dir (== model key).
    selectors = [s.get("directory") for s in json.loads(path.read_text())["fileSelectors"]]
    if model_key not in selectors:
        sys.exit(f"error: {name} fileSelectors {selectors} missing directory {model_key!r}")
    return path


def package(model_key: str, model_dir: Path, out_dir: Path) -> Path:
    manifest = manifest_for(model_key)
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"upmarket-{model_key}.aar"
    with tempfile.TemporaryDirectory() as tmp:
        staging = Path(tmp)
        stage(model_key, model_dir, staging)
        # ba-package resolves the directory selector relative to its CWD.
        cmd = ["xcrun", "ba-package", "package", str(manifest), "--output-path", str(out)]
        print(f"$ (cwd={staging}) {' '.join(cmd)}")
        subprocess.run(cmd, check=True, cwd=staging)
    print(f"✅ {out}")
    return out


def selftest() -> None:
    for key, spec in MODELS.items():
        manifest_for(key)  # validates ID + selector against resources/asset-packs/
        with tempfile.TemporaryDirectory() as tmp:
            model = Path(tmp) / "model"
            model.mkdir()
            for f in spec.expected_files:
                (model / f).write_text(f"stub:{f}")
            staged = stage(key, model, Path(tmp) / "stage")
            for f in spec.expected_files:
                assert (staged / f).is_file(), f"{key}: {f} not staged"
            assert staged.name == key
    print("selftest: ok")


def main() -> int:
    ap = argparse.ArgumentParser(description="Package an Upmarket model as a managed .aar pack.")
    ap.add_argument("--model", choices=sorted(MODELS))
    ap.add_argument("--model-dir", type=Path, help="Directory holding the model files.")
    ap.add_argument("--out-dir", type=Path, default=Path("build/asset-packs"))
    ap.add_argument("--selftest", action="store_true", help="Offline staging/validation check.")
    args = ap.parse_args()

    if args.selftest:
        selftest()
        return 0
    if not args.model:
        ap.error("--model is required")
    if not args.model_dir:
        ap.error("--model-dir is required")
    package(args.model, args.model_dir, args.out_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
