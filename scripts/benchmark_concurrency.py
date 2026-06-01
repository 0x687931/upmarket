#!/usr/bin/env python3
"""Compare serial and parallel conversion throughput on the corpus/pathway matrix."""

import argparse
import concurrent.futures
import json
import os
import subprocess
import sys
import time
from dataclasses import asdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from benchmark_scorer import PATHWAYS, benchmark_host, score_document  # noqa: E402


def load_manifest(corpus: Path) -> list[dict]:
    return json.loads((corpus / "manifest.json").read_text(encoding="utf-8")).get("documents", [])


def resolve_path(corpus: Path, relative: str) -> Path:
    direct = corpus / relative
    if direct.exists():
        return direct
    return corpus / "docling" / "docling" / relative


def ground_truth(corpus: Path, doc: dict) -> str | None:
    key = doc.get("ground_truth")
    if not key:
        return None
    path = resolve_path(corpus, key)
    if not path.exists():
        return None
    return path.read_text(encoding="utf-8", errors="replace")


def timeout_for(pipeline: str) -> int:
    return 120 if pipeline in {"enhanced", "ai"} else 30


def convert_one(doc: dict, corpus: Path, pipeline: str, pathway: str, repeat: int) -> dict:
    file_path = resolve_path(corpus, doc["file"])
    if not file_path.exists():
        return {"doc": doc, "error": "file not found", "elapsed_runs_seconds": []}

    markdown = ""
    elapsed_runs = []
    for _ in range(max(1, repeat)):
        start = time.monotonic()
        proc = subprocess.run(
            [
                sys.executable,
                str(ROOT / "scripts" / "benchmark_scorer.py"),
                "--convert-one",
                str(file_path),
                "--pipeline",
                pipeline,
                "--pathway",
                pathway,
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=timeout_for(pipeline),
            check=False,
        )
        elapsed_wall = time.monotonic() - start
        lines = [line for line in proc.stdout.splitlines() if line.startswith("{")]
        if proc.returncode != 0 or not lines:
            detail = proc.stderr.strip() or proc.stdout.strip() or f"worker exited {proc.returncode}"
            return {"doc": doc, "error": detail[-500:], "elapsed_runs_seconds": elapsed_runs}
        payload = json.loads(lines[-1])
        if not payload.get("success"):
            return {"doc": doc, "error": payload.get("error", "conversion failed"), "elapsed_runs_seconds": elapsed_runs}
        markdown = payload.get("markdown", "")
        elapsed_runs.append(float(payload.get("elapsed_seconds") or elapsed_wall))

    score = score_document(markdown, doc, ground_truth(corpus, doc))
    score.file = doc.get("file", "")
    score.elapsed_runs_seconds = elapsed_runs
    score.elapsed_seconds = sum(elapsed_runs) / len(elapsed_runs) if elapsed_runs else 0.0
    return {"doc": doc, "score": score, "elapsed_runs_seconds": elapsed_runs}


def run_mode(docs: list[dict], corpus: Path, pipeline: str, pathway: str, repeat: int, mode: str, workers: int) -> dict:
    started = time.monotonic()
    before_load = os.getloadavg() if hasattr(os, "getloadavg") else None

    if mode == "serial":
        results = [convert_one(doc, corpus, pipeline, pathway, repeat) for doc in docs]
    else:
        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
            futures = [pool.submit(convert_one, doc, corpus, pipeline, pathway, repeat) for doc in docs]
            results = [future.result() for future in concurrent.futures.as_completed(futures)]

    wall = time.monotonic() - started
    after_load = os.getloadavg() if hasattr(os, "getloadavg") else None
    scores = [item["score"] for item in results if "score" in item]
    failures = [item for item in results if "error" in item]

    return {
        "mode": mode,
        "workers": 1 if mode == "serial" else workers,
        "document_count": len(results),
        "successful_count": len(scores),
        "failed_count": len(failures),
        "wall_time_seconds": round(wall, 3),
        "throughput_docs_per_second": round(len(results) / wall, 4) if wall else 0.0,
        "avg_score_percent": round(sum(score.overall for score in scores) / len(scores) * 100, 1) if scores else 0.0,
        "avg_converter_elapsed_seconds": round(sum(score.elapsed_seconds for score in scores) / len(scores), 4) if scores else 0.0,
        "load_average_before": before_load,
        "load_average_after": after_load,
        "documents": [
            {
                "id": score.doc_id,
                "file": score.file,
                "category": score.category.split("/")[0],
                "overall_percent": round(score.overall * 100, 1),
                "elapsed_seconds": round(score.elapsed_seconds, 3),
                "elapsed_runs_seconds": [round(value, 3) for value in score.elapsed_runs_seconds],
                "error": score.error,
            }
            for score in scores
        ] + [
            {
                "id": item["doc"].get("id", "unknown"),
                "file": item["doc"].get("file", ""),
                "category": item["doc"].get("category", "unknown"),
                "overall_percent": 0.0,
                "elapsed_seconds": 0.0,
                "elapsed_runs_seconds": item.get("elapsed_runs_seconds", []),
                "error": item["error"],
            }
            for item in failures
        ],
    }


def write_markdown(report: dict, path: Path) -> None:
    lines = [
        "# Serial vs Parallel Benchmark",
        "",
        f"Pathway: `{report['pathway']}`",
        f"Documents: {report['document_count']}",
        f"Repeat count: {report['repeat_count']}",
        "",
        "| Mode | Workers | Docs | Failures | Avg Score | Converter Avg | Wall Time | Throughput | Load Before | Load After |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |",
    ]
    for result in report["results"]:
        before = ", ".join(f"{value:.2f}" for value in result["load_average_before"] or [])
        after = ", ".join(f"{value:.2f}" for value in result["load_average_after"] or [])
        lines.append(
            f"| {result['mode']} | {result['workers']} | {result['document_count']} | {result['failed_count']} | "
            f"{result['avg_score_percent']}% | {result['avg_converter_elapsed_seconds']}s | "
            f"{result['wall_time_seconds']}s | {result['throughput_docs_per_second']} | {before} | {after} |"
        )

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--corpus", type=Path, default=Path("tests/corpus"))
    parser.add_argument("--pathway", required=True, choices=sorted(PATHWAYS))
    parser.add_argument("--category", default="")
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--repeat", type=int, default=1)
    parser.add_argument("--workers", type=int, default=max(2, min(4, (os.cpu_count() or 4) // 2)))
    parser.add_argument("--json-output", type=Path, default=Path("reports/concurrency-benchmark.json"))
    parser.add_argument("--markdown-output", type=Path, default=Path("reports/concurrency-benchmark.md"))
    args = parser.parse_args()

    pathway_config = PATHWAYS[args.pathway]
    pipeline = pathway_config["pipeline"]
    docs = [
        doc for doc in load_manifest(args.corpus)
        if doc.get("category") in pathway_config["valid_categories"]
    ]
    if args.category:
        docs = [doc for doc in docs if doc.get("category", "").startswith(args.category)]
    if args.limit > 0:
        docs = docs[:args.limit]
    if not docs:
        raise SystemExit("no benchmark documents matched")

    corpus_root = str(args.corpus.resolve())
    existing_roots = os.environ.get("UPMARKET_ALLOWED_INPUT_ROOTS")
    os.environ["UPMARKET_ALLOWED_INPUT_ROOTS"] = corpus_root if not existing_roots else existing_roots + os.pathsep + corpus_root
    os.environ.setdefault("TMPDIR", str((ROOT / "build" / "benchmark-tmp").resolve()))

    report = {
        "version": 1,
        "pathway": args.pathway,
        "pipeline": pipeline,
        "document_count": len(docs),
        "repeat_count": max(1, args.repeat),
        "benchmark_host": benchmark_host("auto"),
        "results": [
            run_mode(docs, args.corpus, pipeline, args.pathway, args.repeat, "serial", args.workers),
            run_mode(docs, args.corpus, pipeline, args.pathway, args.repeat, "parallel", args.workers),
        ],
    }

    args.json_output.parent.mkdir(parents=True, exist_ok=True)
    args.json_output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    write_markdown(report, args.markdown_output)
    print(f"JSON report: {args.json_output}")
    print(f"Markdown report: {args.markdown_output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
