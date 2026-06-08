#!/usr/bin/env python3
"""Validate that installed packages match an exact-pinned requirements file."""

from __future__ import annotations

import argparse
import importlib.metadata
import re
import sys
from pathlib import Path


REQUIREMENT_RE = re.compile(r"^\s*([A-Za-z0-9_.-]+)\s*==\s*([^,\s]+)")


def normalize(name: str) -> str:
    return name.lower().replace("_", "-")


def load_pins(path: Path) -> dict[str, tuple[str, str]]:
    pins: dict[str, tuple[str, str]] = {}
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.split("#", 1)[0].strip()
        if not line or line.startswith("-"):
            continue
        match = REQUIREMENT_RE.match(line)
        if match is None:
            raise ValueError(f"{path}:{number}: expected exact == requirement")
        name, version = match.groups()
        pins[normalize(name)] = (name, version)
    return pins


def installed_version(name: str) -> str | None:
    try:
        return importlib.metadata.version(name)
    except importlib.metadata.PackageNotFoundError:
        return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--requirements", default="requirements.txt")
    args = parser.parse_args()

    pins = load_pins(Path(args.requirements))
    errors: list[str] = []

    for normalized, (name, expected) in sorted(pins.items()):
        actual = installed_version(normalized) or installed_version(name)
        if actual is None:
            errors.append(f"{name}: not installed, expected {expected}")
        elif actual != expected:
            errors.append(f"{name}: installed {actual}, expected {expected}")

    if errors:
        print("\n".join(f"error: {error}" for error in errors))
        return 1

    print(f"ok: installed packages match {args.requirements} ({len(pins)} packages)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
