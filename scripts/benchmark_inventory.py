#!/usr/bin/env python3
"""Record forensic benchmark tool, host, and corpus inventory."""

from __future__ import annotations

import importlib.metadata
import json
import platform
import shutil
import subprocess
import hashlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPORT_JSON = ROOT / "reports" / "benchmark-inventory.json"
REPORT_MD = ROOT / "docs" / "release" / "BENCHMARK_INVENTORY.md"
BENCHMARK_CACHE = ROOT / "reports" / "benchmark-cache"

PYTHON_PACKAGES = [
    "docling",
    "docling-core",
    "docling-parse",
    "docling-ibm-models",
    "markitdown",
    "pypdfium2",
    "PyMuPDF",
    "rapidocr",
    "onnxruntime",
    "paddleocr",
    "paddlepaddle",
    "torch",
    "torchvision",
    "transformers",
    "huggingface-hub",
    "Pillow",
    "numpy",
]

BINARIES = {
    "pdftotext": ["pdftotext", "-v"],
}


def run(command: list[str], cwd: Path | None = None) -> dict:
    try:
        proc = subprocess.run(command, cwd=cwd or ROOT, capture_output=True, text=True, timeout=10)
        return {
            "command": command,
            "returncode": proc.returncode,
            "stdout": proc.stdout.strip(),
            "stderr": proc.stderr.strip(),
        }
    except Exception as exc:
        return {"command": command, "error": str(exc)}


def git_value(args: list[str], cwd: Path) -> str | None:
    result = run(["git", *args], cwd=cwd)
    if result.get("returncode") == 0:
        return result.get("stdout", "").strip()
    return None


def host_inventory() -> dict:
    host = {
        "system": platform.system(),
        "release": platform.release(),
        "machine": platform.machine(),
        "processor": platform.processor(),
        "mac_version": platform.mac_ver()[0],
    }
    if platform.system() == "Darwin":
        for key in ("machdep.cpu.brand_string", "hw.memsize", "hw.ncpu"):
            result = run(["sysctl", "-n", key])
            if result.get("returncode") == 0:
                host[key] = result.get("stdout", "")
    return host


def short(value: str | None, limit: int = 160) -> str:
    if not value:
        return "-"
    value = " ".join(str(value).split())
    if len(value) > limit:
        return value[: limit - 3] + "..."
    return value


def project_url(metadata) -> str | None:
    urls = metadata.get_all("Project-URL") or []
    for value in urls:
        if "," in value:
            label, url = value.split(",", 1)
            if label.strip().lower() in {"homepage", "source", "repository", "documentation"}:
                return url.strip()
    return metadata.get("Home-page")


def package_inventory() -> list[dict]:
    rows = []
    for name in PYTHON_PACKAGES:
        item = {"name": name, "installed": False}
        try:
            dist = importlib.metadata.distribution(name)
            item.update({
                "installed": True,
                "version": dist.version,
                "location": str(Path(dist.locate_file(""))),
                "metadata_name": dist.metadata.get("Name"),
                "summary": short(dist.metadata.get("Summary")),
                "source": project_url(dist.metadata),
                "license": short(dist.metadata.get("License-Expression") or dist.metadata.get("License")),
            })
        except importlib.metadata.PackageNotFoundError:
            pass
        rows.append(item)
    return rows


def binary_inventory() -> list[dict]:
    rows = []
    for name, command in BINARIES.items():
        path = shutil.which(command[0])
        item = {"name": name, "installed": path is not None, "path": path}
        if path:
            result = run(command)
            item["version_output"] = "\n".join(filter(None, [result.get("stdout", ""), result.get("stderr", "")]))
        rows.append(item)
    return rows


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def model_cache_inventory() -> list[dict]:
    model_root = BENCHMARK_CACHE / "paddlex" / "official_models"
    if not model_root.exists():
        return []

    rows = []
    for model_dir in sorted(path for path in model_root.iterdir() if path.is_dir()):
        files = sorted(path for path in model_dir.rglob("*") if path.is_file())
        hashes = [
            {
                "path": str(path.relative_to(model_dir)),
                "sha256": file_sha256(path),
                "bytes": path.stat().st_size,
            }
            for path in files
        ]
        rows.append({
            "name": model_dir.name,
            "path": str(model_dir),
            "file_count": len(files),
            "total_bytes": sum(item["bytes"] for item in hashes),
            "files": hashes,
        })
    return rows


def corpus_inventory() -> dict:
    corpus_root = ROOT / "tests" / "corpus"
    manifest = corpus_root / "manifest.json"
    data = json.loads(manifest.read_text(encoding="utf-8"))
    docling_repo = corpus_root / "docling" / "docling"
    return {
        "manifest": str(manifest.relative_to(ROOT)),
        "document_count": len(data.get("documents", [])),
        "docling_repo_commit": git_value(["rev-parse", "HEAD"], docling_repo) if docling_repo.exists() else None,
        "docling_repo_remote": git_value(["remote", "get-url", "origin"], docling_repo) if docling_repo.exists() else None,
        "docling_repo_dirty": git_value(["status", "--short"], docling_repo) if docling_repo.exists() else None,
    }


def table(headers: list[str], rows: list[list[str]]) -> list[str]:
    lines = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    for row in rows:
        lines.append("| " + " | ".join(str(cell).replace("|", "\\|").replace("\n", "<br>") for cell in row) + " |")
    return lines


def write_markdown(inventory: dict) -> None:
    packages = inventory["python_packages"]
    binaries = inventory["binaries"]
    host = inventory["host"]
    cache = inventory["cache"]
    corpus = inventory["corpus"]
    models = inventory["model_cache"]
    model_lines = table(
        ["Model", "Path", "Files", "Bytes"],
        [[model["name"], model["path"], str(model["file_count"]), str(model["total_bytes"])] for model in models],
    ) if models else ["No benchmark model cache artifacts found."]

    lines = [
        "# Benchmark Inventory",
        "",
        "Generated by `scripts/benchmark_inventory.py`. This is a forensic record of the local benchmark environment.",
        "",
        "## Host",
        "",
        *table(["Key", "Value"], [[key, value] for key, value in host.items()]),
        "",
        "## Cache Roots",
        "",
        *table(["Environment", "Path"], [[key, value] for key, value in cache.items()]),
        "",
        "## Model Cache",
        "",
        *model_lines,
        "",
        "## Corpus",
        "",
        *table(["Key", "Value"], [[key, value] for key, value in corpus.items()]),
        "",
        "## Python Packages",
        "",
        *table(
            ["Package", "Installed", "Version", "Location", "License", "Source"],
            [
                [
                    pkg["name"],
                    str(pkg.get("installed", False)),
                    pkg.get("version", "-"),
                    pkg.get("location", "-"),
                    pkg.get("license", "-"),
                    pkg.get("source") or "-",
                ]
                for pkg in packages
            ],
        ),
        "",
        "## Binaries",
        "",
        *table(
            ["Binary", "Installed", "Path", "Version Output"],
            [[binary["name"], str(binary.get("installed", False)), binary.get("path", "-"), binary.get("version_output", "-")] for binary in binaries],
        ),
        "",
    ]
    REPORT_MD.parent.mkdir(parents=True, exist_ok=True)
    REPORT_MD.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    BENCHMARK_CACHE.mkdir(parents=True, exist_ok=True)
    inventory = {
        "host": host_inventory(),
        "cache": {
            "UPMARKET_MODELS_DIR": str((BENCHMARK_CACHE / "upmarket-models").resolve()),
            "PADDLE_PDX_CACHE_HOME": str((BENCHMARK_CACHE / "paddlex").resolve()),
            "PADDLE_HOME": str((BENCHMARK_CACHE / "paddle").resolve()),
            "HF_HOME": str((BENCHMARK_CACHE / "huggingface").resolve()),
            "MODELSCOPE_CACHE": str((BENCHMARK_CACHE / "modelscope").resolve()),
            "XDG_CACHE_HOME": str((BENCHMARK_CACHE / "xdg").resolve()),
        },
        "corpus": corpus_inventory(),
        "model_cache": model_cache_inventory(),
        "python_packages": package_inventory(),
        "binaries": binary_inventory(),
    }
    REPORT_JSON.parent.mkdir(parents=True, exist_ok=True)
    REPORT_JSON.write_text(json.dumps(inventory, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_markdown(inventory)
    print(f"ok: wrote {REPORT_JSON} and {REPORT_MD}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
