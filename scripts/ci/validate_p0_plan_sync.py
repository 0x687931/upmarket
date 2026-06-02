#!/usr/bin/env python3
"""Validate that the P0 registry, implementation plan, and release docs stay aligned."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


REGISTRY = Path("docs/release/p0_task_registry.json")
PLAN = Path("docs/IMPLEMENTATION_PLAN.md")
ORCHESTRATION = Path("docs/release/AGENT_TASK_ORCHESTRATION.md")
CI_WORKFLOW = Path(".github/workflows/ci.yml")


def fail(errors: list[str]) -> int:
    for error in errors:
        print(f"error: {error}", file=sys.stderr)
    return 1


def p0_plan_section(text: str) -> str:
    start = text.find("## P0 Audit Blockers")
    end = text.find("## Verified Complete")
    if start == -1:
        return ""
    if end == -1:
        return text[start:]
    return text[start:end]


def main() -> int:
    errors: list[str] = []

    for path in (REGISTRY, PLAN, ORCHESTRATION, CI_WORKFLOW):
        if not path.exists():
            errors.append(f"required file missing: {path}")
    if errors:
        return fail(errors)

    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    tasks = registry.get("tasks", [])
    plan_text = PLAN.read_text(encoding="utf-8")
    p0_text = p0_plan_section(plan_text)
    orchestration_text = ORCHESTRATION.read_text(encoding="utf-8")
    ci_text = CI_WORKFLOW.read_text(encoding="utf-8")

    headings = set(re.findall(r"^### (P0 - .+)$", p0_text, flags=re.MULTILINE))
    release_gates = {task.get("release_gate") for task in tasks}

    for gate in sorted(release_gates):
        if gate not in headings:
            errors.append(f"{REGISTRY}: release gate '{gate}' has no matching heading in {PLAN}")

    for heading in sorted(headings):
        if heading not in release_gates:
            errors.append(f"{PLAN}: heading '{heading}' has no matching task release_gate in {REGISTRY}")

    required_scope_paths = {
        "docs/IMPLEMENTATION_PLAN.md",
        "docs/release/p0_task_registry.json",
    }
    p011 = next((task for task in tasks if task.get("id") == "P0-011"), None)
    if p011 is None:
        errors.append(f"{REGISTRY}: P0-011 is required for task automation")
    else:
        scope = set(p011.get("scope", []))
        missing_scope = sorted(required_scope_paths - scope)
        for path in missing_scope:
            errors.append(f"{REGISTRY}: P0-011 scope must include {path}")

    required_doc_phrases = [
        "Main Codex Integration Gate",
        "updated `docs/IMPLEMENTATION_PLAN.md`",
        "scripts/ci/validate_p0_plan_sync.py",
    ]
    for phrase in required_doc_phrases:
        if phrase not in orchestration_text:
            errors.append(f"{ORCHESTRATION}: missing required integration guidance: {phrase}")

    for command in (
        "scripts/ci/validate_task_registry.py",
        "scripts/ci/validate_p0_plan_sync.py",
    ):
        if command not in ci_text:
            errors.append(f"{CI_WORKFLOW}: missing PR CI command {command}")

    if errors:
        return fail(errors)

    print(f"ok: P0 plan sync covers {len(tasks)} task(s) and {len(headings)} release gate(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
