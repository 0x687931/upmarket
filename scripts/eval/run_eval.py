#!/usr/bin/env python3
"""Run upmarket-cli over the evaluation corpus and score output against ground truth.

    scripts/eval/run_eval.py                      # all pairs, --auto routing
    scripts/eval/run_eval.py --engine --basic     # force a route
    scripts/eval/run_eval.py --format docx --limit 5 --show-fail

Scoring is a word-sequence similarity ratio (0..1) between CLI output and ground
truth — a coarse fidelity proxy, not an exact match. Reports per-format and overall
averages plus any conversions that errored.
"""
from __future__ import annotations
import argparse, difflib, json, os, subprocess, sys, tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
MANIFEST = REPO / "tests" / "corpus" / "manifest.json"


def find_cli() -> str | None:
    if env := os.environ.get("UPMARKET_CLI"):
        return env
    roots = [REPO / "build", Path.home() / "Library/Developer/Xcode/DerivedData"]
    for root in roots:
        hits = sorted(root.glob("**/upmarket-cli")) if root.exists() else []
        hits = [h for h in hits if h.is_file() and os.access(h, os.X_OK)]
        if hits:
            return str(hits[0])
    return None


def similarity(output: str, truth: str) -> float:
    a, b = output.split(), truth.split()
    if not b:
        return 1.0 if not a else 0.0
    return difflib.SequenceMatcher(None, a, b).ratio()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", default="auto",
                    choices=["auto", "basic", "native", "pro", "complex", "max", "ai"],
                    help="CLI routing (mapped to --<engine>)")
    ap.add_argument("--format", default="", help="Only evaluate this format")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--show-fail", action="store_true", help="Print errored conversions")
    args = ap.parse_args()

    cli = find_cli()
    if not cli:
        print("error: upmarket-cli not found — build it or set UPMARKET_CLI", file=sys.stderr)
        return 2
    if not MANIFEST.exists():
        print(f"error: {MANIFEST} not found — run scripts/eval/fetch_corpus.sh first", file=sys.stderr)
        return 2

    docs = json.loads(MANIFEST.read_text())["documents"]
    if args.format:
        docs = [d for d in docs if d["format"] == args.format]
    if args.limit:
        docs = docs[: args.limit]

    by_fmt: dict[str, list[float]] = {}
    failures: list[tuple[str, str]] = []
    for d in docs:
        document, truth = REPO / d["document"], REPO / d["ground_truth"]
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "out.md"
            proc = subprocess.run(
                [cli, str(document), f"--{args.engine}", "-o", str(out), "--force"],
                capture_output=True, text=True,
            )
            if proc.returncode != 0 or not out.exists():
                failures.append((d["id"], (proc.stderr.strip() or f"exit {proc.returncode}")[:100]))
                by_fmt.setdefault(d["format"], []).append(0.0)
                continue
            ratio = similarity(out.read_text(errors="ignore"), truth.read_text(errors="ignore"))
            by_fmt.setdefault(d["format"], []).append(ratio)

    print(f"\nEngine --{args.engine} — {len(docs)} documents (cli: {Path(cli).name})\n")
    print(f"{'format':<10} {'n':>4} {'avg score':>10}")
    print("-" * 28)
    all_scores: list[float] = []
    for fmt in sorted(by_fmt):
        scores = by_fmt[fmt]
        all_scores += scores
        print(f"{fmt:<10} {len(scores):>4} {sum(scores)/len(scores):>10.3f}")
    print("-" * 28)
    if all_scores:
        print(f"{'OVERALL':<10} {len(all_scores):>4} {sum(all_scores)/len(all_scores):>10.3f}")
    print(f"\nerrored: {len(failures)}")
    if args.show_fail:
        for doc_id, msg in failures:
            print(f"  ✗ {doc_id}: {msg}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
