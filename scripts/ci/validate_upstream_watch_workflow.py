#!/usr/bin/env python3
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "nightly-upstream.yml"
WATCH = ROOT / "scripts" / "ci" / "watch_upstream.py"


def require(text: str, needle: str, label: str) -> bool:
    if needle in text:
        return True
    print(f"error: upstream watch workflow missing {label}: {needle}", file=sys.stderr)
    return False


def main() -> int:
    workflow = WORKFLOW.read_text(encoding="utf-8")
    watch = WATCH.read_text(encoding="utf-8")

    checks = [
        require(workflow, "scripts/ci/watch_upstream.py", "report generator"),
        require(workflow, "reports/upstream-watch.json", "JSON artifact"),
        require(workflow, "reports/upstream-watch.md", "Markdown artifact"),
        require(workflow, "scripts/update_dependencies.sh --check-only", "check-only dependency validation"),
        require(workflow, "issues: write", "issue write permission"),
        require(workflow, "pkg.tracking_mode", "issue tracking-mode field"),
        require(workflow, "pkg.current_version", "issue current-version field"),
        require(workflow, "pkg.candidate_version", "issue candidate-version field"),
        require(workflow, "pkg.latest_version", "issue latest-version field"),
        require(workflow, "Required adoption gate before promotion", "adoption gate wording"),
        require(watch, '"tracking_mode": requirement.tracking_mode', "report tracking-mode field"),
        require(watch, '"current_version": requirement.declared_version', "report current-version field"),
        require(watch, '"candidate_version": candidate.declared_version if candidate else None', "report candidate-version field"),
        require(watch, '"latest_version": None', "report latest-version field"),
    ]

    if not all(checks):
        return 1

    print("ok: upstream watch workflow is wired to the report contract")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
