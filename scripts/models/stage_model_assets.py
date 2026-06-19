#!/usr/bin/env python3
"""Stage an Upmarket AI model into a hostable archive + manifest.

The app downloads Max-tier models via FirstPartyModelDownloadService (debug/GitHub CDN) and
Background Assets (release/Apple CDN), both of which fetch `<base-url>/<key>.json` and a tar.gz
the app extracts into its models directory. This tool produces both for either model.

    # 1. get the weights (one-time; needs `pip install huggingface_hub`)
    scripts/models/stage_model_assets.py --model lfm25_vl --download --model-dir build/lfm25_vl

    # 2. stage archive + manifest, pointing at where you'll host the tar.gz
    scripts/models/stage_model_assets.py --model lfm25_vl \
        --model-dir build/lfm25_vl \
        --archive-url https://github.com/<org>/<repo>/releases/download/models/lfm25_vl.tar.gz \
        --out-dir build/model-assets

Then upload build/model-assets/{<key>.tar.gz, <key>.json} to that base URL (or App Store
Connect → Additional Resources for the Background Assets path).

Each MODELS entry below MUST match its counterpart in the Swift catalogs — the app rejects any
manifest whose version/key/source/revision/storage_dir/expected_* differ:
  - upmarket_ai: FirstPartyModelDownloadService.ModelDownloadCatalog + BackgroundAssetsDownloadService.modelSpec
  - lfm25_vl:    same two sites
"""
from __future__ import annotations
import argparse, hashlib, json, subprocess, sys, tarfile, tempfile
from dataclasses import dataclass, field
from pathlib import Path

MANIFEST_VERSION = 1


@dataclass(frozen=True)
class ModelSpec:
    key: str
    source_id: str
    revision: str
    hf_repo: str
    expected_files: list[str]
    expected_dirs: list[str] = field(default_factory=list)

    @property
    def storage_dir(self) -> str:
        return self.key


# --- Must mirror the Swift catalogs (see module docstring) ---
MODELS: dict[str, ModelSpec] = {
    "upmarket_ai": ModelSpec(
        key="upmarket_ai",
        source_id="com.upmarket.models.upmarket-ai",
        revision="e9939db25d2f296c8678d0491c4609a8c596c50a",
        hf_repo="ibm-granite/granite-docling-258M-mlx",
        expected_files=[
            "added_tokens.json", "chat_template.jinja", "config.json", "generation_config.json",
            "merges.txt", "model.safetensors", "model.safetensors.index.json",
            "preprocessor_config.json", "processor_config.json", "special_tokens_map.json",
            "tokenizer.json", "tokenizer_config.json", "vocab.json",
        ],
    ),
    "lfm25_vl": ModelSpec(
        key="lfm25_vl",
        source_id="com.upmarket.models.lfm25-vl",
        revision="051260290c8361562915be1b0292636a6ac8a7a3",
        hf_repo="mlx-community/LFM2.5-VL-1.6B-8bit",
        expected_files=[
            "chat_template.jinja", "config.json", "generation_config.json", "model.safetensors",
            "model.safetensors.index.json", "processor_config.json",
            "tokenizer.json", "tokenizer_config.json",
        ],
    ),
}


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def download(spec: ModelSpec, model_dir: Path) -> None:
    model_dir.mkdir(parents=True, exist_ok=True)
    cmd = ["hf", "download", spec.hf_repo, "--revision", spec.revision,
           "--local-dir", str(model_dir), *spec.expected_files]
    print(f"$ {' '.join(cmd)}")
    subprocess.run(cmd, check=True)


def stage(spec: ModelSpec, model_dir: Path, archive_url: str, out_dir: Path) -> Path:
    missing = [f for f in spec.expected_files if not (model_dir / f).is_file()]
    if missing:
        sys.exit(f"error: model-dir missing expected files: {', '.join(missing)}")

    out_dir.mkdir(parents=True, exist_ok=True)
    archive = out_dir / f"{spec.key}.tar.gz"
    # Files go at the archive root (no top-level dir): the app extracts straight into
    # the model storage directory and validates expected_files relative to it.
    with tarfile.open(archive, "w:gz") as tar:
        for name in spec.expected_files:
            tar.add(model_dir / name, arcname=name)

    manifest = {
        "manifest_version": MANIFEST_VERSION,
        "model_key": spec.key,
        "source_id": spec.source_id,
        "revision": spec.revision,
        "storage_dir": spec.storage_dir,
        "expected_files": spec.expected_files,
        "expected_dirs": spec.expected_dirs,
        "archive": {
            "url": archive_url,
            "sha256": sha256_of(archive),
            "bytes": archive.stat().st_size,
        },
        "files": [],  # archive path: per-file list is unused but the schema requires the key
    }
    manifest_path = out_dir / f"{spec.key}.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")

    mb = manifest["archive"]["bytes"] / (1 << 20)
    print(f"✅ {archive.name} ({mb:.0f} MB)  sha256={manifest['archive']['sha256'][:12]}…")
    print(f"✅ {manifest_path.name}")
    print(f"→ upload both to the directory served at {archive_url.rsplit('/', 1)[0]}/")
    return manifest_path


def selftest() -> None:
    for spec in MODELS.values():
        with tempfile.TemporaryDirectory() as tmp:
            model = Path(tmp) / "model"
            model.mkdir()
            for f in spec.expected_files:
                (model / f).write_text(f"stub:{f}")
            out = Path(tmp) / "out"
            url = f"https://example.com/models/{spec.key}.tar.gz"
            mpath = stage(spec, model, url, out)
            m = json.loads(mpath.read_text())
            assert m["model_key"] == spec.key and m["revision"] == spec.revision
            assert m["expected_files"] == spec.expected_files
            assert m["archive"]["url"] == url
            assert m["archive"]["sha256"] == sha256_of(out / f"{spec.key}.tar.gz")
            assert m["archive"]["bytes"] > 0
    print("selftest: ok")


def main() -> int:
    ap = argparse.ArgumentParser(description="Stage an Upmarket AI model archive + manifest.")
    ap.add_argument("--model", choices=sorted(MODELS), help="Which model to stage.")
    ap.add_argument("--model-dir", type=Path, help="Directory holding the model files.")
    ap.add_argument("--archive-url", help="Public URL where the .tar.gz will be hosted.")
    ap.add_argument("--out-dir", type=Path, default=Path("build/model-assets"))
    ap.add_argument("--download", action="store_true", help="Fetch the weights into --model-dir via `hf`.")
    ap.add_argument("--selftest", action="store_true", help="Run an offline round-trip check and exit.")
    args = ap.parse_args()

    if args.selftest:
        selftest()
        return 0
    if not args.model:
        ap.error("--model is required")
    spec = MODELS[args.model]
    if not args.model_dir:
        ap.error("--model-dir is required")
    if args.download:
        download(spec, args.model_dir)
    if not args.archive_url:
        ap.error("--archive-url is required to write the manifest")
    stage(spec, args.model_dir, args.archive_url, args.out_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
