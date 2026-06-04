#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
EXTENSION = ROOT / "Nova" / "Upmarket.novaextension"
MANIFEST = EXTENSION / "extension.json"


def command_entries(commands: dict) -> list[dict]:
    entries: list[dict] = []
    for group in ("editor", "extensions", "command-palette", "text"):
        for entry in commands.get(group, []):
            if isinstance(entry, dict) and "command" in entry:
                entries.append(entry)
    return entries


def main() -> int:
    if not MANIFEST.exists():
        print(f"error: missing Nova extension manifest: {MANIFEST}", file=sys.stderr)
        return 1

    try:
        manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        print(f"error: invalid Nova extension manifest JSON: {exc}", file=sys.stderr)
        return 1

    required = ["identifier", "name", "organization", "version", "description", "main", "commands"]
    missing = [key for key in required if key not in manifest]
    if missing:
        print(f"error: Nova extension manifest missing {', '.join(missing)}", file=sys.stderr)
        return 1

    main_path = EXTENSION / manifest["main"]
    if not main_path.exists():
        print(f"error: Nova extension main script is missing: {main_path}", file=sys.stderr)
        return 1

    source = main_path.read_text(encoding="utf-8")
    registered = set(re.findall(r'nova\.commands\.register\("([^"]+)"', source))
    declared = {entry["command"] for entry in command_entries(manifest["commands"])}
    missing_handlers = sorted(declared - registered)
    if missing_handlers:
        print(f"error: Nova commands missing registered handlers: {', '.join(missing_handlers)}", file=sys.stderr)
        return 1

    entitlements = manifest.get("entitlements", {})
    if entitlements.get("process") is not True:
        print("error: Nova extension must declare process entitlement for CLI use", file=sys.stderr)
        return 1
    if entitlements.get("clipboard") is not True:
        print("error: Nova extension must declare clipboard entitlement for copy command", file=sys.stderr)
        return 1
    if entitlements.get("filesystem") != "readwrite":
        print("error: Nova extension must declare readwrite filesystem entitlement for temporary output", file=sys.stderr)
        return 1

    if re.search(r"\bshell\s*:\s*true\b", source):
        print("error: Nova extension must not run CLI through a shell", file=sys.stderr)
        return 1

    print("ok: Nova extension manifest and command handlers are valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
