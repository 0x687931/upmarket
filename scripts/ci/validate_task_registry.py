#!/usr/bin/env python3
"""Validate the agent task registry used for P0 release work."""

from __future__ import annotations

import json
import sys
from pathlib import Path


REGISTRY = Path("docs/release/p0_task_registry.json")
REQUIRED_FIELDS = {
    "id",
    "title",
    "objective",
    "owner",
    "scope",
    "non_goals",
    "acceptance",
    "release_gate",
    "risk",
    "labels",
}
KNOWN_LABELS = {
    "p0-blocker",
    "gate-a-build",
    "gate-b-conversion",
    "gate-c-stability",
    "gate-d-storekit",
    "gate-e-listing",
    "area-swift",
    "area-python",
    "area-security",
    "area-release",
    "area-ux",
    "agent-ready",
    "needs-human",
    "upstream-watch",
    "upstream-candidate",
    "upstream-adopted",
    "upstream-rejected",
    "upstream-blocked",
    "upstream-fork",
}


def fail(message: str) -> int:
    print(f"error: {message}", file=sys.stderr)
    return 1


def main() -> int:
    if not REGISTRY.exists():
        return fail(f"task registry not found: {REGISTRY}")

    data = json.loads(REGISTRY.read_text(encoding="utf-8"))
    tasks = data.get("tasks")
    if not isinstance(tasks, list) or not tasks:
        return fail("registry must contain a non-empty tasks array")

    ids: set[str] = set()
    errors: list[str] = []

    for index, task in enumerate(tasks, start=1):
        task_id = str(task.get("id", f"task #{index}"))
        missing = REQUIRED_FIELDS - set(task)
        if missing:
            errors.append(f"{task_id}: missing fields: {', '.join(sorted(missing))}")
            continue

        if task_id in ids:
            errors.append(f"{task_id}: duplicate id")
        ids.add(task_id)

        if not task_id.startswith("P0-"):
            errors.append(f"{task_id}: id must start with P0-")

        for field in ("scope", "non_goals", "acceptance", "risk", "labels"):
            value = task[field]
            if not isinstance(value, list) or not value:
                errors.append(f"{task_id}: {field} must be a non-empty list")

        unknown_labels = sorted(set(task["labels"]) - KNOWN_LABELS)
        if unknown_labels:
            errors.append(f"{task_id}: unknown labels: {', '.join(unknown_labels)}")

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print(f"ok: validated {len(tasks)} P0 task(s) in {REGISTRY}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
