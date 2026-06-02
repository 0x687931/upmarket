#!/usr/bin/env python3
"""Run a built Upmarket app briefly with Xcode's Main Thread Checker enabled."""

from __future__ import annotations

import argparse
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path


MAIN_THREAD_CHECKER = Path("/Applications/Xcode.app/Contents/Developer/usr/lib/libMainThreadChecker.dylib")


def executable_for(app_path: Path) -> Path:
    executable = app_path / "Contents" / "MacOS" / "Upmarket"
    if not executable.exists():
        raise SystemExit(f"error: missing app executable: {executable}")
    return executable


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-path", required=True, help="path to built Upmarket.app")
    parser.add_argument("--duration", type=float, default=10.0, help="seconds to keep the app running")
    args = parser.parse_args()

    if not MAIN_THREAD_CHECKER.exists():
        raise SystemExit(f"error: missing Main Thread Checker runtime: {MAIN_THREAD_CHECKER}")

    app_path = Path(args.app_path)
    executable_for(app_path)

    temporary = tempfile.TemporaryDirectory(prefix="upmarket-mtc-")
    trace_path = Path(temporary.name) / "main-thread-checker.trace"
    process = subprocess.Popen(
        [
            "xcrun",
            "xctrace",
            "record",
            "--template",
            "Time Profiler",
            "--output",
            str(trace_path),
            "--time-limit",
            f"{args.duration:.0f}s",
            "--no-prompt",
            "--env",
            f"DYLD_INSERT_LIBRARIES={MAIN_THREAD_CHECKER}",
            "--env",
            "MTC_CRASH_ON_REPORT=1",
            "--launch",
            "--",
            str(app_path),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    deadline = time.monotonic() + args.duration + 30
    while time.monotonic() < deadline:
        if process.poll() is not None:
            break
        time.sleep(0.1)

    if process.poll() is None:
        process.terminate()
        try:
            stdout, stderr = process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            stdout, stderr = process.communicate(timeout=5)
    else:
        stdout, stderr = process.communicate(timeout=5)

    temporary.cleanup()

    output = "\n".join(part for part in (stdout, stderr) if part)
    lower_output = output.lower()
    if "main thread checker" in lower_output or "ui api called on a background thread" in lower_output:
        print(output, file=sys.stderr)
        return 1

    return_code = process.returncode
    expected_stops = {-signal.SIGTERM, 0, 54}
    if return_code not in expected_stops:
        print(output, file=sys.stderr)
        return return_code or 1

    print(f"ok: Main Thread Checker found no launch-time violations in {args.duration:.1f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
