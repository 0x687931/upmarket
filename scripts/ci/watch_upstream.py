#!/usr/bin/env python3
"""Report upstream dependency drift without changing the working tree."""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


REQUIREMENT_RE = re.compile(r"^\s*([A-Za-z0-9_.-]+)\s*([^#\s]*)?")
PIN_RE = re.compile(r"==\s*([^,\s]+)")
FLOOR_RE = re.compile(r">=\s*([^,\s]+)")


UPSTREAM_PROJECTS = {
    "docling": "Docling",
    "docling-core": "Docling",
    "docling-parse": "Docling",
    "torch": "Torch / MLX",
    "torchvision": "Torch / MLX",
    "mlx": "Torch / MLX",
    "mlx-vlm": "Torch / MLX",
    "huggingface_hub": "Hugging Face Hub",
    "transformers": "Transformers",
    "pypdfium2": "pypdfium2 / PyMuPDF",
    "pydantic": "Other",
    "Pillow": "Other",
}


@dataclass(frozen=True)
class Requirement:
    name: str
    specifier: str
    declared_version: str
    tracking_mode: str


def parse_requirement(line: str) -> Requirement | None:
    line = line.split("#", 1)[0].strip()
    if not line or line.startswith("-"):
        return None

    match = REQUIREMENT_RE.match(line)
    if not match:
        return None

    name = match.group(1)
    specifier = match.group(2) or ""
    pin = PIN_RE.search(specifier)
    floor = FLOOR_RE.search(specifier)

    if pin:
        return Requirement(name, specifier, pin.group(1), "pinned")
    if floor:
        return Requirement(name, specifier, floor.group(1), "minimum")
    return Requirement(name, specifier, "", "unbounded")


def load_requirements(path: Path) -> list[Requirement]:
    requirements: list[Requirement] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        requirement = parse_requirement(line)
        if requirement:
            requirements.append(requirement)
    return requirements


def fetch_latest_version(package: str) -> str:
    url = f"https://pypi.org/pypi/{package}/json"
    request = urllib.request.Request(url, headers={"User-Agent": "upmarket-upstream-watch"})
    with urllib.request.urlopen(request, timeout=20) as response:
        payload = json.loads(response.read().decode("utf-8"))
    return str(payload["info"]["version"])


def build_report(requirements: list[Requirement]) -> dict:
    packages = []
    has_candidates = False

    for requirement in requirements:
        package = {
            "name": requirement.name,
            "upstream_project": UPSTREAM_PROJECTS.get(requirement.name, "Other"),
            "specifier": requirement.specifier,
            "declared_version": requirement.declared_version,
            "tracking_mode": requirement.tracking_mode,
            "latest_version": None,
            "status": "unknown",
            "error": None,
        }

        try:
            latest = fetch_latest_version(requirement.name)
            package["latest_version"] = latest
            if requirement.declared_version and latest == requirement.declared_version:
                package["status"] = "current"
            else:
                package["status"] = "upstream-candidate"
                has_candidates = True
        except (KeyError, TimeoutError, urllib.error.URLError, urllib.error.HTTPError) as exc:
            package["status"] = "blocked"
            package["error"] = str(exc)

        packages.append(package)

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source": "requirements.txt",
        "has_candidates": has_candidates,
        "has_findings": has_candidates or any(package["status"] == "blocked" for package in packages),
        "packages": packages,
    }


def write_markdown(report: dict, path: Path) -> None:
    lines = [
        "# Upstream Watch Report",
        "",
        f"Generated: `{report['generated_at']}`",
        f"Source: `{report['source']}`",
        "",
        "| Package | Project | Declared | Latest | Status |",
        "| --- | --- | --- | --- | --- |",
    ]

    for package in report["packages"]:
        declared = package["declared_version"] or package["specifier"] or "unbounded"
        latest = package["latest_version"] or "unknown"
        lines.append(
            f"| `{package['name']}` | {package['upstream_project']} | "
            f"`{declared}` | `{latest}` | `{package['status']}` |"
        )

    lines.extend(
        [
            "",
            "## Required Next Steps",
            "",
            "For each `upstream-candidate`, create or update an upstream intake issue before adoption.",
            "Do not promote a candidate without a reproduction/corpus case, dependency audit, offline smoke, rollback plan, and security/privacy review.",
        ]
    )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--requirements", default="requirements.txt")
    parser.add_argument("--json-out", default="reports/upstream-watch.json")
    parser.add_argument("--markdown-out", default="reports/upstream-watch.md")
    parser.add_argument("--fail-on-blocked", action="store_true")
    args = parser.parse_args()

    requirements_path = Path(args.requirements)
    if not requirements_path.exists():
        print(f"error: requirements file not found: {requirements_path}", file=sys.stderr)
        return 2

    report = build_report(load_requirements(requirements_path))

    json_path = Path(args.json_out)
    markdown_path = Path(args.markdown_out)
    json_path.parent.mkdir(parents=True, exist_ok=True)
    markdown_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_markdown(report, markdown_path)

    candidate_count = sum(1 for package in report["packages"] if package["status"] == "upstream-candidate")
    blocked_count = sum(1 for package in report["packages"] if package["status"] == "blocked")
    print(f"ok: upstream watch wrote {json_path} and {markdown_path}")
    print(f"summary: {candidate_count} candidate(s), {blocked_count} blocked check(s)")

    if args.fail_on_blocked and blocked_count:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
