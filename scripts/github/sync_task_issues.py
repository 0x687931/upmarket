#!/usr/bin/env python3
"""Create or update GitHub labels/issues from the P0 task registry.

Default mode is dry-run. Pass --apply to write to GitHub using the gh CLI.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path


REGISTRY = Path("docs/release/p0_task_registry.json")

LABELS = {
    "p0-blocker": ("b60205", "Blocks v1.0 release readiness"),
    "gate-a-build": ("1d76db", "Build, archive, plist, entitlements, packaging"),
    "gate-b-conversion": ("0e8a16", "Conversion reliability and corpus behavior"),
    "gate-c-stability": ("fbca04", "Stability, liveness, diagnostics, fault injection"),
    "gate-d-storekit": ("d93f0b", "StoreKit, signing, App Store Connect"),
    "gate-e-listing": ("5319e7", "Legal, privacy, listing, screenshots"),
    "area-swift": ("c2e0c6", "Swift, SwiftUI, AppKit, StoreKit, Apple APIs"),
    "area-python": ("bfdadc", "Python bridge, packages, models, upstream runtime"),
    "area-security": ("f9d0c4", "Sandbox, privacy, supply chain, redaction"),
    "area-release": ("d4c5f9", "CI, release gates, automation, process"),
    "area-ux": ("fef2c0", "Usability, accessibility, product behavior"),
    "agent-ready": ("ededed", "Scoped enough for Codex or specialist agent work"),
    "needs-human": ("cccccc", "Requires human account access, judgement, or manual review"),
    "upstream-watch": ("6f42c1", "Tracked upstream item; no adoption yet"),
    "upstream-candidate": ("fbca04", "Upstream change is ready for local validation"),
    "upstream-adopted": ("0e8a16", "Validated upstream change has been adopted"),
    "upstream-rejected": ("b60205", "Upstream change was rejected for this app"),
    "upstream-blocked": ("d93f0b", "Waiting on upstream, security, license, or release review"),
}


def run(command: list[str], *, input_text: str | None = None, apply: bool) -> subprocess.CompletedProcess[str] | None:
    if not apply:
        print("$ " + " ".join(command))
        return None
    return subprocess.run(command, input=input_text, text=True, check=True, capture_output=True)


def gh_json(command: list[str]) -> object:
    result = subprocess.run(command, text=True, check=True, capture_output=True)
    return json.loads(result.stdout)


def issue_body(task: dict) -> str:
    def bullets(items: list[str]) -> str:
        return "\n".join(f"- {item}" for item in items)

    return f"""## Objective
{task["objective"]}

## Owner
{task["owner"]}

## Scope
{bullets(task["scope"])}

## Non-goals
{bullets(task["non_goals"])}

## Acceptance Criteria
{bullets(task["acceptance"])}

## Release Gate
{task["release_gate"]}

## Risk Areas
{bullets(task["risk"])}

## Automation
Source: `docs/release/p0_task_registry.json`
Task ID: `{task["id"]}`
"""


def sync_label(name: str, apply: bool) -> None:
    color, description = LABELS[name]
    run(["gh", "label", "create", name, "--color", color, "--description", description, "--force"], apply=apply)


def find_issue(task_id: str) -> int | None:
    issues = gh_json(
        [
            "gh",
            "issue",
            "list",
            "--state",
            "all",
            "--search",
            f"{task_id} in:title",
            "--json",
            "number,title,state",
            "--limit",
            "20",
        ]
    )
    for issue in issues:
        if task_id in issue["title"]:
            return int(issue["number"])
    return None


def sync_issue(task: dict, apply: bool) -> None:
    title = f"[{task['id']}] {task['title']}"
    body = issue_body(task)
    labels: list[str] = task["labels"]

    if not apply:
        print(f"# issue: {title}")
        print(f"# labels: {', '.join(labels)}")
        return

    issue_number = find_issue(task["id"])
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as body_file:
        body_file.write(body)
        body_path = body_file.name

    try:
        if issue_number is None:
            command = ["gh", "issue", "create", "--title", title, "--body-file", body_path]
            for label in labels:
                command.extend(["--label", label])
            run(command, apply=True)
        else:
            command = ["gh", "issue", "edit", str(issue_number), "--title", title, "--body-file", body_path]
            for label in labels:
                command.extend(["--add-label", label])
            run(command, apply=True)
    finally:
        Path(body_path).unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="write labels/issues to GitHub")
    parser.add_argument("--registry", default=str(REGISTRY))
    args = parser.parse_args()

    registry = Path(args.registry)
    if not registry.exists():
        print(f"error: registry not found: {registry}", file=sys.stderr)
        return 2

    data = json.loads(registry.read_text(encoding="utf-8"))
    tasks = data["tasks"]

    if args.apply:
        subprocess.run(["gh", "auth", "status"], check=True)

    label_names = sorted(LABELS)
    for label in label_names:
        sync_label(label, args.apply)

    for task in tasks:
        sync_issue(task, args.apply)

    mode = "applied" if args.apply else "dry-run"
    print(f"ok: {mode} sync for {len(tasks)} task(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
