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
    "docling-ibm-models": "Docling",
    "markitdown": "MarkItDown",
    "torch": "Torch / MLX",
    "torchvision": "Torch / MLX",
    "mlx": "Torch / MLX",
    "mlx-vlm": "Torch / MLX",
    "huggingface_hub": "Hugging Face Hub",
    "transformers": "Transformers",
    "pypdfium2": "pypdfium2",
    "mammoth": "Other",
    "python-pptx": "Other",
    "openpyxl": "Other",
    "pydantic": "Other",
    "Pillow": "Other",
    "numpy": "Other",
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


def by_name(requirements: list[Requirement]) -> dict[str, Requirement]:
    return {requirement.name.lower().replace("_", "-"): requirement for requirement in requirements}


def fetch_latest_version(package: str) -> str:
    url = f"https://pypi.org/pypi/{package}/json"
    request = urllib.request.Request(url, headers={"User-Agent": "upmarket-upstream-watch"})
    with urllib.request.urlopen(request, timeout=20) as response:
        payload = json.loads(response.read().decode("utf-8"))
    return str(payload["info"]["version"])


def build_report(requirements: list[Requirement], candidate_requirements: list[Requirement]) -> dict:
    packages = []
    has_candidates = False
    candidates_by_name = by_name(candidate_requirements)

    for requirement in requirements:
        normalized_name = requirement.name.lower().replace("_", "-")
        candidate = candidates_by_name.get(normalized_name)
        package = {
            "name": requirement.name,
            "upstream_project": UPSTREAM_PROJECTS.get(requirement.name, "Other"),
            "specifier": requirement.specifier,
            "declared_version": requirement.declared_version,
            "tracking_mode": requirement.tracking_mode,
            "current_version": requirement.declared_version,
            "candidate_version": candidate.declared_version if candidate else None,
            "latest_version": None,
            "status": "unknown",
            "error": None,
        }

        try:
            latest = fetch_latest_version(requirement.name)
            package["latest_version"] = latest
            if candidate and candidate.declared_version != requirement.declared_version:
                package["status"] = "candidate"
                has_candidates = True
            elif requirement.declared_version and latest == requirement.declared_version:
                package["status"] = "current"
            else:
                package["status"] = "latest-upstream"
                has_candidates = True
        except (KeyError, TimeoutError, urllib.error.URLError, urllib.error.HTTPError) as exc:
            package["status"] = "blocked"
            package["error"] = str(exc)

        packages.append(package)

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "source": "requirements.txt",
        "candidate_source": "requirements-candidate.txt",
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
        "| Package | Project | Tracking | Current | Candidate | Latest | Status |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]

    for package in report["packages"]:
        current = package["current_version"] or package["specifier"] or "unbounded"
        candidate = package["candidate_version"] or current
        latest = package["latest_version"] or "unknown"
        lines.append(
            f"| `{package['name']}` | {package['upstream_project']} | "
            f"`{package['tracking_mode']}` | `{current}` | `{candidate}` | `{latest}` | `{package['status']}` |"
        )

    lines.extend(
        [
            "",
            "## Required Next Steps",
            "",
            "For each `latest-upstream` or `candidate`, create or update an upstream intake issue before adoption.",
            "Do not promote a candidate without a reproduction/corpus case, dependency audit, offline smoke, rollback plan, and security/privacy review.",
        ]
    )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--requirements", default="requirements.txt")
    parser.add_argument("--candidate-requirements", default="requirements-candidate.txt")
    parser.add_argument("--json-out", default="reports/upstream-watch.json")
    parser.add_argument("--markdown-out", default="reports/upstream-watch.md")
    parser.add_argument("--fail-on-blocked", action="store_true")
    args = parser.parse_args()

    requirements_path = Path(args.requirements)
    candidate_requirements_path = Path(args.candidate_requirements)
    for path in (requirements_path, candidate_requirements_path):
        if not path.exists():
            print(f"error: requirements file not found: {path}", file=sys.stderr)
            return 2

    report = build_report(load_requirements(requirements_path), load_requirements(candidate_requirements_path))

    json_path = Path(args.json_out)
    markdown_path = Path(args.markdown_out)
    json_path.parent.mkdir(parents=True, exist_ok=True)
    markdown_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_markdown(report, markdown_path)

    candidate_count = sum(1 for package in report["packages"] if package["status"] in {"candidate", "latest-upstream"})
    blocked_count = sum(1 for package in report["packages"] if package["status"] == "blocked")
    print(f"ok: upstream watch wrote {json_path} and {markdown_path}")
    print(f"summary: {candidate_count} candidate(s), {blocked_count} blocked check(s)")

    if args.fail_on_blocked and blocked_count:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
