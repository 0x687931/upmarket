#!/usr/bin/env python3
"""Smoke-test the bundled Upmarket MCP stdio server."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
APP_GROUP_ID = "group.com.upmarket.app"


def resolve_binary(argument: str) -> Path:
    path = Path(argument)
    if path.suffix == ".app":
        return path / "Contents" / "MacOS" / "upmarket-mcp"
    return path


def assert_app_commands(argument: str) -> None:
    app_path = Path(argument)
    if app_path.suffix != ".app":
        return

    command_dir = app_path / "Contents" / "MacOS"
    for name in ("upmarket-cli", "upmarket-mcp"):
        command = command_dir / name
        if not command.is_file():
            raise AssertionError(f"{name} missing from app bundle: {command}")
        if not os.access(command, os.X_OK):
            raise AssertionError(f"{name} is not executable in app bundle: {command}")


def run_session(binary: Path, state_root: Path, messages: list[dict], extra_env: dict[str, str] | None = None) -> list[dict]:
    env = os.environ.copy()
    env["UPMARKET_MCP_STATE_ROOT"] = str(state_root)
    if extra_env:
        env.update(extra_env)
    proc = subprocess.run(
        [str(binary)],
        input="".join(json.dumps(message, separators=(",", ":")) + "\n" for message in messages),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        timeout=10,
        check=False,
    )
    if proc.returncode != 0:
        raise AssertionError(f"{binary} exited {proc.returncode}: {proc.stderr.strip()}")

    responses: list[dict] = []
    for line in proc.stdout.splitlines():
        try:
            responses.append(json.loads(line))
        except json.JSONDecodeError as exc:
            raise AssertionError(f"non-JSON stdout from MCP server: {line!r}") from exc
    return responses


def signed_entitlements(binary: Path) -> str:
    result = subprocess.run(
        ["codesign", "-d", "--entitlements", "-", str(binary)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
        check=False,
    )
    if result.returncode != 0:
        return ""
    return result.stdout or result.stderr


def signed_binary_uses_app_group_sandbox(binary: Path) -> bool:
    entitlements = signed_entitlements(binary)
    return (
        "com.apple.security.app-sandbox" in entitlements
        and "[Bool] true" in entitlements
        and APP_GROUP_ID in entitlements
    )


@contextmanager
def temporary_state_root(binary: Path, prefix: str):
    parent: Path | None = None
    if signed_binary_uses_app_group_sandbox(binary):
        parent = Path.home() / "Library" / "Group Containers" / APP_GROUP_ID / "MCPValidation"
        try:
            parent.mkdir(parents=True, exist_ok=True)
        except OSError as exc:
            raise AssertionError(f"unable to prepare app group MCP smoke root: {parent}") from exc

    with tempfile.TemporaryDirectory(prefix=prefix, dir=parent) as tmp:
        yield Path(tmp)


def should_skip_stdio_smoke_in_xcode_script_sandbox() -> bool:
    return (
        os.environ.get("ENABLE_USER_SCRIPT_SANDBOXING") == "YES"
        and os.environ.get("UPMARKET_RUN_MCP_SMOKE_IN_BUILD") != "1"
    )


def write_state(state_root: Path, enabled: bool) -> None:
    state_dir = state_root / "MCP"
    state_dir.mkdir(parents=True, exist_ok=True)
    (state_dir / "advertisement.json").write_text(
        json.dumps(
            {
                "version": 1,
                "enabled": enabled,
                "updatedAt": "2026-06-04T00:00:00Z",
                "commandPath": "/tmp/upmarket-mcp",
            }
        ),
        encoding="utf-8",
    )


def write_fake_cli(path: Path, script: str) -> None:
    path.write_text(script, encoding="utf-8")
    path.chmod(0o755)


def response_by_id(responses: list[dict], response_id: int) -> dict:
    for response in responses:
        if response.get("id") == response_id:
            return response
    raise AssertionError(f"missing response id {response_id}: {responses}")


def assert_disabled(binary: Path) -> None:
    with temporary_state_root(binary, "upmarket-mcp-disabled-") as root:
        responses = run_session(
            binary,
            root,
            [
                {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "initialize",
                    "params": {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "ci"}},
                },
                {"jsonrpc": "2.0", "method": "notifications/initialized"},
                {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
                {
                    "jsonrpc": "2.0",
                    "id": 3,
                    "method": "tools/call",
                    "params": {"name": "convert_document_to_markdown", "arguments": {"input_path": "/tmp/nope.pdf"}},
                },
            ],
        )
        tools = response_by_id(responses, 2)["result"]["tools"]
        if tools != []:
            raise AssertionError(f"disabled MCP server advertised tools: {tools}")
        result = response_by_id(responses, 3)["result"]
        if result.get("isError") is not True:
            raise AssertionError(f"disabled direct tool call did not return a tool error: {result}")


def assert_enabled(binary: Path) -> None:
    with temporary_state_root(binary, "upmarket-mcp-enabled-") as root:
        write_state(root, enabled=True)
        responses = run_session(
            binary,
            root,
            [
                {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "method": "initialize",
                    "params": {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "ci"}},
                },
                {"jsonrpc": "2.0", "method": "notifications/initialized"},
                {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
                {
                    "jsonrpc": "2.0",
                    "id": 3,
                    "method": "tools/call",
                    "params": {
                        "name": "convert_document_to_markdown",
                        "arguments": {"input_path": "/tmp/upmarket-mcp-unauthorized.pdf"},
                    },
                },
            ],
        )
        tools = response_by_id(responses, 2)["result"]["tools"]
        names = [tool.get("name") for tool in tools]
        if names != ["convert_document_to_markdown"]:
            raise AssertionError(f"enabled MCP server advertised unexpected tools: {tools}")
        result = response_by_id(responses, 3)["result"]
        if result.get("isError") is not True:
            raise AssertionError(f"enabled MCP server accepted an unstaged input path: {result}")
        text = result.get("content", [{}])[0].get("text", "")
        if "staged" not in text:
            raise AssertionError(f"enabled MCP server returned the wrong unstaged-path error: {result}")


def convert_message(input_path: Path, response_id: int = 3, return_mode: str = "inline") -> dict:
    return {
        "jsonrpc": "2.0",
        "id": response_id,
        "method": "tools/call",
        "params": {
            "name": "convert_document_to_markdown",
            "arguments": {
                "input_path": str(input_path),
                "return_mode": return_mode,
                "max_chars": 1000,
            },
        },
    }


def assert_cli_success_nonzero_and_timeout(binary: Path) -> None:
    with temporary_state_root(binary, "upmarket-mcp-cli-") as root:
        write_state(root, enabled=True)
        input_dir = root / "MCP" / "Inputs"
        input_dir.mkdir(parents=True, exist_ok=True)
        input_file = input_dir / "input.pdf"
        input_file.write_bytes(b"%PDF-1.7\n")
        fake_cli = root / "fake-upmarket-cli"

        write_fake_cli(
            fake_cli,
            """#!/bin/sh
set -eu
printf '# Converted\\n' > "$4"
""",
        )
        responses = run_session(
            binary,
            root,
            [convert_message(input_file)],
            extra_env={"UPMARKET_MCP_CLI_PATH": str(fake_cli)},
        )
        result = response_by_id(responses, 3)["result"]
        if result.get("isError") is not False:
            raise AssertionError(f"MCP fake CLI success returned error: {result}")
        text = result.get("content", [{}])[0].get("text", "")
        if "# Converted" not in text:
            raise AssertionError(f"MCP fake CLI success returned wrong text: {result}")

        write_fake_cli(
            fake_cli,
            """#!/bin/sh
set -eu
printf '\\377\\376\\375' > "$4"
""",
        )
        responses = run_session(
            binary,
            root,
            [convert_message(input_file, response_id=6, return_mode="file")],
            extra_env={"UPMARKET_MCP_CLI_PATH": str(fake_cli)},
        )
        result = response_by_id(responses, 6)["result"]
        if result.get("isError") is not False:
            raise AssertionError(f"MCP file-mode invalid UTF-8 output returned error: {result}")
        structured = result.get("structuredContent", {})
        if structured.get("returned") != "file":
            raise AssertionError(f"MCP file-mode invalid UTF-8 output was not returned as file: {result}")
        output_path = structured.get("output_path")
        if not output_path or not Path(output_path).is_file():
            raise AssertionError(f"MCP file-mode output path missing: {result}")
        Path(output_path).unlink()

        write_fake_cli(
            fake_cli,
            """#!/bin/sh
set -eu
echo 'This file cannot be converted safely.' >&2
exit 2
""",
        )
        responses = run_session(
            binary,
            root,
            [convert_message(input_file, response_id=4)],
            extra_env={"UPMARKET_MCP_CLI_PATH": str(fake_cli)},
        )
        result = response_by_id(responses, 4)["result"]
        if result.get("isError") is not True:
            raise AssertionError(f"MCP fake CLI nonzero did not return tool error: {result}")
        if "converted safely" not in result.get("content", [{}])[0].get("text", ""):
            raise AssertionError(f"MCP fake CLI nonzero returned wrong error: {result}")

        write_fake_cli(
            fake_cli,
            """#!/bin/sh
set -eu
printf 'partial output\\n' > "$4"
sleep 5
""",
        )
        responses = run_session(
            binary,
            root,
            [convert_message(input_file, response_id=5)],
            extra_env={
                "UPMARKET_MCP_CLI_PATH": str(fake_cli),
                "UPMARKET_MCP_CLI_TIMEOUT_SECONDS": "0.2",
            },
        )
        result = response_by_id(responses, 5)["result"]
        if result.get("isError") is not True:
            raise AssertionError(f"MCP fake CLI timeout did not return tool error: {result}")
        if "timed out" not in result.get("content", [{}])[0].get("text", ""):
            raise AssertionError(f"MCP fake CLI timeout returned wrong error: {result}")

        output_dir = root / "MCP" / "Outputs"
        leftovers = list(output_dir.glob("upmarket-mcp-*")) if output_dir.exists() else []
        if leftovers:
            raise AssertionError(f"MCP timeout left partial outputs behind: {leftovers}")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: scripts/ci/validate_mcp_server.py /path/to/Upmarket.app-or-upmarket-mcp", file=sys.stderr)
        return 2

    assert_app_commands(sys.argv[1])

    binary = resolve_binary(sys.argv[1])
    if not binary.is_file():
        print(f"error: MCP server binary missing: {binary}", file=sys.stderr)
        return 1
    if not os.access(binary, os.X_OK):
        print(f"error: MCP server binary is not executable: {binary}", file=sys.stderr)
        return 1

    if should_skip_stdio_smoke_in_xcode_script_sandbox():
        print("warning: skipping MCP stdio smoke inside Xcode's user script sandbox")
        print("ok: Upmarket MCP server packaging is configured")
        return 0

    assert_disabled(binary)
    assert_enabled(binary)
    assert_cli_success_nonzero_and_timeout(binary)
    print("ok: Upmarket MCP server stdio smoke passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
