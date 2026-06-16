#!/usr/bin/env python3
"""Stage the Upmarket AI (Granite-Docling mlx) model into a hostable archive + manifest.

The app downloads the Max-tier model via FirstPartyModelDownloadService, which fetches
`<base-url>/upmarket_ai.json` and (for the archive path) a tar.gz it extracts into the
models directory. This tool produces both: it tars the model files and writes the manifest
the service validates against its built-in catalog.

    # 1. get the weights (one-time; needs `pip install huggingface_hub`)
    scripts/models/stage_model_assets.py --download --model-dir build/upmarket_ai

    # 2. stage archive + manifest, pointing at where you'll host the tar.gz
    scripts/models/stage_model_assets.py \
        --model-dir build/upmarket_ai \
        --archive-url https://github.com/<org>/<repo>/releases/download/models/upmarket_ai.tar.gz \
        --out-dir build/model-assets

Then upload build/model-assets/{upmarket_ai.tar.gz, upmarket_ai.json} to that base URL.

The SPEC block below MUST match FirstPartyModelDownloadService.ModelDownloadCatalog — the
app rejects any manifest whose version/key/source/revision/storage_dir/expected_* differ.
"""
from __future__ import annotations
import argparse, hashlib, json, subprocess, sys, tarfile, tempfile
from pathlib import Path

# --- Must mirror FirstPartyModelDownloadService.ModelDownloadCatalog ---
MANIFEST_VERSION = 1
MODEL_KEY = "upmarket_ai"
SOURCE_ID = "com.upmarket.models.upmarket-ai"
REVISION = "e9939db25d2f296c8678d0491c4609a8c596c50a"
STORAGE_DIR = "upmarket_ai"
HF_REPO = "ibm-granite/granite-docling-258M-mlx"
EXPECTED_FILES = [
    "added_tokens.json", "chat_template.jinja", "config.json", "generation_config.json",
    "merges.txt", "model.safetensors", "model.safetensors.index.json",
    "preprocessor_config.json", "processor_config.json", "special_tokens_map.json",
    "tokenizer.json", "tokenizer_config.json", "vocab.json",
]
EXPECTED_DIRS: list[str] = []


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def download(model_dir: Path) -> None:
    model_dir.mkdir(parents=True, exist_ok=True)
    cmd = ["hf", "download", HF_REPO, "--revision", REVISION,
           "--local-dir", str(model_dir), *EXPECTED_FILES]
    print(f"$ {' '.join(cmd)}")
    subprocess.run(cmd, check=True)


def stage(model_dir: Path, archive_url: str, out_dir: Path) -> Path:
    missing = [f for f in EXPECTED_FILES if not (model_dir / f).is_file()]
    if missing:
        sys.exit(f"error: model-dir missing expected files: {', '.join(missing)}")

    out_dir.mkdir(parents=True, exist_ok=True)
    archive = out_dir / f"{MODEL_KEY}.tar.gz"
    # Files go at the archive root (no top-level dir): the app extracts straight into
    # the model storage directory and validates expected_files relative to it.
    with tarfile.open(archive, "w:gz") as tar:
        for name in EXPECTED_FILES:
            tar.add(model_dir / name, arcname=name)

    manifest = {
        "manifest_version": MANIFEST_VERSION,
        "model_key": MODEL_KEY,
        "source_id": SOURCE_ID,
        "revision": REVISION,
        "storage_dir": STORAGE_DIR,
        "expected_files": EXPECTED_FILES,
        "expected_dirs": EXPECTED_DIRS,
        "archive": {
            "url": archive_url,
            "sha256": sha256_of(archive),
            "bytes": archive.stat().st_size,
        },
        "files": [],  # archive path: per-file list is unused but the schema requires the key
    }
    manifest_path = out_dir / f"{MODEL_KEY}.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")

    mb = manifest["archive"]["bytes"] / (1 << 20)
    print(f"✅ {archive.name} ({mb:.0f} MB)  sha256={manifest['archive']['sha256'][:12]}…")
    print(f"✅ {manifest_path.name}")
    print(f"→ upload both to the directory served at {archive_url.rsplit('/', 1)[0]}/")
    return manifest_path


def selftest() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        model = Path(tmp) / "model"
        model.mkdir()
        for f in EXPECTED_FILES:
            (model / f).write_text(f"stub:{f}")
        out = Path(tmp) / "out"
        url = "https://example.com/models/upmarket_ai.tar.gz"
        mpath = stage(model, url, out)
        m = json.loads(mpath.read_text())
        assert m["model_key"] == MODEL_KEY and m["revision"] == REVISION
        assert m["expected_files"] == EXPECTED_FILES
        assert m["archive"]["url"] == url
        assert m["archive"]["sha256"] == sha256_of(out / f"{MODEL_KEY}.tar.gz")
        assert m["archive"]["bytes"] > 0
        print("selftest: ok")


def main() -> int:
    ap = argparse.ArgumentParser(description="Stage the Upmarket AI model archive + manifest.")
    ap.add_argument("--model-dir", type=Path, help="Directory holding the model files.")
    ap.add_argument("--archive-url", help="Public URL where the .tar.gz will be hosted.")
    ap.add_argument("--out-dir", type=Path, default=Path("build/model-assets"))
    ap.add_argument("--download", action="store_true", help="Fetch the weights into --model-dir via `hf`.")
    ap.add_argument("--selftest", action="store_true", help="Run an offline round-trip check and exit.")
    args = ap.parse_args()

    if args.selftest:
        selftest()
        return 0
    if not args.model_dir:
        ap.error("--model-dir is required")
    if args.download:
        download(args.model_dir)
    if not args.archive_url:
        ap.error("--archive-url is required to write the manifest")
    stage(args.model_dir, args.archive_url, args.out_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
