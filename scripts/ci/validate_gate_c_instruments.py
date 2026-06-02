#!/usr/bin/env python3
"""Validate Gate C Instruments trace inventory and owner interpretation."""

from __future__ import annotations

import subprocess
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TRACE_ROOT = ROOT / "reports" / "gate-c-stability"
DEFAULT_EXPORT_TIMEOUT_SECONDS = 45


class TraceExportError(RuntimeError):
    pass


@dataclass(frozen=True)
class TraceExpectation:
    path: str
    template: str | None
    target: str
    min_duration: float
    max_duration: float | None
    usable: bool
    reason: str
    export_timeout: int = DEFAULT_EXPORT_TIMEOUT_SECONDS


EXPECTATIONS = [
    TraceExpectation(
        path="allocations.trace",
        template="Allocations",
        target="Upmarket",
        min_duration=100.0,
        max_duration=120.0,
        usable=True,
        reason="Upmarket-targeted Allocations capture",
        export_timeout=120,
    ),
    TraceExpectation(
        path="time-profiler.trace",
        template="Time Profiler",
        target="Upmarket",
        min_duration=8.0,
        max_duration=20.0,
        usable=True,
        reason="Upmarket-targeted Time Profiler capture",
    ),
    TraceExpectation(
        path="time-profiler-all-processes.trace",
        template="Time Profiler",
        target="all-processes",
        min_duration=5.0,
        max_duration=8.0,
        usable=False,
        reason="all-process inventory, not Upmarket-targeted release evidence",
    ),
    TraceExpectation(
        path="leaks.trace",
        template="Leaks",
        target="Upmarket",
        min_duration=8.0,
        max_duration=20.0,
        usable=False,
        reason="targeted Leaks attempt hit task-port authorization errors during recording",
    ),
    TraceExpectation(
        path="leaks-all-processes.trace",
        template=None,
        target="all-processes",
        min_duration=0.0,
        max_duration=0.0,
        usable=False,
        reason="zero-duration empty run",
    ),
    TraceExpectation(
        path="allocations-all-processes.trace",
        template=None,
        target="all-processes",
        min_duration=0.0,
        max_duration=0.0,
        usable=False,
        reason="zero-duration empty run",
    ),
]


def export_toc(trace: Path, timeout: int) -> ET.Element:
    try:
        result = subprocess.run(
            ["xcrun", "xctrace", "export", "--input", str(trace), "--toc"],
            check=True,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.CalledProcessError as error:
        raise TraceExportError(f"xctrace export failed: {error.stderr.strip()}") from error
    except subprocess.TimeoutExpired as error:
        raise TraceExportError(f"xctrace export timed out after {timeout}s") from error

    try:
        return ET.fromstring(result.stdout)
    except ET.ParseError as error:
        raise TraceExportError(f"xctrace exported invalid XML: {error}") from error


def text(root: ET.Element, path: str) -> str:
    node = root.find(path)
    return (node.text or "").strip() if node is not None else ""


def target_label(root: ET.Element) -> str:
    target = root.find("./run/info/target")
    if target is None:
        return ""
    process = target.find("process")
    if process is not None:
        return process.attrib.get("name", "")
    if target.find("all-processes") is not None:
        return "all-processes"
    return ""


def duration(root: ET.Element) -> float:
    raw = text(root, "./run/info/summary/duration")
    return float(raw or "0")


def validate(expectation: TraceExpectation) -> list[str]:
    trace = TRACE_ROOT / expectation.path
    if not trace.exists():
        return [f"{expectation.path}: missing trace bundle"]

    errors: list[str] = []
    try:
        root = export_toc(trace, expectation.export_timeout)
    except TraceExportError as error:
        if expectation.usable:
            return [f"{expectation.path}: {error}"]
        print(f"{expectation.path}: not release evidence; {expectation.reason}; export={error}")
        return []

    actual_target = target_label(root)
    if actual_target != expectation.target:
        errors.append(f"{expectation.path}: target {actual_target!r}, expected {expectation.target!r}")

    actual_duration = duration(root)
    if actual_duration < expectation.min_duration:
        errors.append(
            f"{expectation.path}: duration {actual_duration:.3f}s below expected {expectation.min_duration:.3f}s"
        )
    if expectation.max_duration is not None and actual_duration > expectation.max_duration:
        errors.append(
            f"{expectation.path}: duration {actual_duration:.3f}s above expected {expectation.max_duration:.3f}s"
        )

    actual_template = text(root, "./run/info/summary/template-name") or None
    if actual_template != expectation.template:
        errors.append(f"{expectation.path}: template {actual_template!r}, expected {expectation.template!r}")

    has_data = root.find("./run/data/table") is not None
    if expectation.usable and not has_data:
        errors.append(f"{expectation.path}: expected usable trace data, found none")
    if not expectation.usable and expectation.target == "all-processes" and actual_target != "all-processes":
        errors.append(f"{expectation.path}: non-release evidence must stay labeled all-processes")

    status = "usable" if expectation.usable else "not release evidence"
    print(f"{expectation.path}: {status}; {expectation.reason}; duration={actual_duration:.3f}s")
    return errors


def main() -> int:
    errors: list[str] = []
    for expectation in EXPECTATIONS:
        errors.extend(validate(expectation))

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print("ok: Gate C Instruments trace interpretation matches recorded evidence")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
