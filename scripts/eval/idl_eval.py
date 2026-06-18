#!/usr/bin/env python3
"""IDL whole-page eval: convert real docs with upmarket-cli, score text vs Textract GT.

Three subcommands:

  fetch [N] [--shard S]   Stream pixparse/idl-wds, cache N docs into tests/corpus/idl/
                          as {key}.pdf + {key}.gt.txt + {key}.png. Run once.
  score [--engine FLAG]   Convert every cached .pdf with upmarket-cli, write {key}.<eng>.md,
                          score word-similarity vs GT, print a table + mean, append idl_results.jsonl.
  show KEY                Print GT | MD side by side for one doc (diagnose structure).

Caching means the fix->rebuild->rescore loop is fully offline and deterministic.

GT is AWS Textract OCR text (silver labels: plain lines, NO markdown structure). So the
NUMBER measures text-extraction / reading-order fidelity and is blind to table/heading
markup. Use it to catch regressions across all docs; use `show` + the .png to judge
STRUCTURE. For table structure specifically, use the TEDS harness (score.py).

ponytail: word-level difflib ratio, zero-dep. The score is a regression gauge, not truth
 — the page render + GT are the ground for judging fixes.
"""
import sys, json, tarfile, tempfile, subprocess, urllib.request, difflib, argparse, glob, os
from pathlib import Path
from statistics import mean

CORPUS = Path("tests/corpus/idl")
RESULTS = Path("scripts/eval/idl_results.jsonl")
SHARD_URL = "https://huggingface.co/datasets/pixparse/idl-wds/resolve/main/idl-train-{:05d}.tar"


def find_cli() -> str:
    if env := os.environ.get("UPMARKET_CLI"):
        return env
    pats = ["build/DerivedData/Build/Products/Debug/upmarket-cli",
            "/Users/*/Library/Developer/Xcode/DerivedData/Upmarket-*/Build/Products/Debug/upmarket-cli"]
    hits = [h for p in pats for h in glob.glob(p)]
    return max(hits, key=os.path.getmtime) if hits else ""


def gt_text(meta: dict) -> str:
    lines = []
    for page in meta.get("pages", []):
        lines.extend(page.get("text", []))
    return "\n".join(lines)


def fetch(n: int, shard: int) -> int:
    CORPUS.mkdir(parents=True, exist_ok=True)
    url = SHARD_URL.format(shard)
    print(f"streaming {url} -> {CORPUS}/")
    resp = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "idl-eval"}))
    tar = tarfile.open(fileobj=resp, mode="r|")  # sequential stream, no full download
    pend, done = {}, 0
    for m in tar:
        if not m.isfile():
            continue
        key, _, ext = m.name.rpartition(".")
        if ext not in ("pdf", "json"):
            continue  # skip tif/ocr
        pend.setdefault(key, {})[ext] = tar.extractfile(m).read()
        s = pend.pop(key) if {"pdf", "json"} <= set(pend.get(key, {})) else None
        if not s:
            continue
        (CORPUS / f"{key}.pdf").write_bytes(s["pdf"])
        (CORPUS / f"{key}.gt.txt").write_text(gt_text(json.loads(s["json"])), encoding="utf-8")
        subprocess.run(["sips", "-s", "format", "png", str(CORPUS / f"{key}.pdf"),
                        "--out", str(CORPUS / f"{key}.png")], capture_output=True)
        print(f"  cached {key}")
        done += 1
        if done >= n:
            break
    tar.close(); resp.close()
    print(f"\ncached {done} docs in {CORPUS}/ (pdf + gt.txt + png)")
    return 0


def score(engine: str, cli: str, timeout: int) -> int:
    if not cli or not Path(cli).exists():
        print(f"upmarket-cli not found ({cli!r}). Build UpmarketCLI or set $UPMARKET_CLI.")
        return 1
    pdfs = sorted(CORPUS.glob("*.pdf"))
    if not pdfs:
        print(f"no docs in {CORPUS}/ — run `fetch` first.")
        return 1
    eng = engine.lstrip("-") or "auto"
    rows = []
    with RESULTS.open("a", encoding="utf-8") as log:
        for pdf in pdfs:
            key = pdf.stem
            gt = (CORPUS / f"{key}.gt.txt").read_text(encoding="utf-8")
            out = CORPUS / f"{key}.{eng}.md"
            cmd = [cli, str(pdf), "-o", str(out), "--force"] + ([engine] if engine else [])
            try:
                r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
                status = "ok" if r.returncode == 0 else f"err:{r.returncode}"
            except subprocess.TimeoutExpired:
                status = "timeout"
            md = out.read_text(encoding="utf-8") if out.exists() else ""
            sim = difflib.SequenceMatcher(None, gt.split(), md.split()).ratio()
            row = {"key": key, "engine": eng, "status": status,
                   "gt_words": len(gt.split()), "md_words": len(md.split()), "sim": round(sim, 4)}
            rows.append(row)
            log.write(json.dumps(row) + "\n")
            print(f"{key:<12} {status:<8} gt={row['gt_words']:>5}w md={row['md_words']:>5}w  sim={sim:.3f}")
    if rows:
        print(f"\nengine={eng}  n={len(rows)}  mean sim={mean(r['sim'] for r in rows):.3f}"
              f"  -> {RESULTS}  (inspect: idl_eval.py show <key>)")
    return 0


def show(key: str) -> int:
    gt = (CORPUS / f"{key}.gt.txt")
    mds = sorted(CORPUS.glob(f"{key}.*.md"))
    if not gt.exists():
        print(f"no GT for {key} in {CORPUS}/"); return 1
    print(f"=== {key} | page: {CORPUS}/{key}.png ===\n--- GT (Textract) ---")
    print(gt.read_text(encoding="utf-8"))
    for md in mds:
        print(f"\n--- MD ({md.suffixes[-2].lstrip('.')}) ---")
        print(md.read_text(encoding="utf-8"))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("fetch"); f.add_argument("n", nargs="?", type=int, default=5); f.add_argument("--shard", type=int, default=0)
    s = sub.add_parser("score"); s.add_argument("--engine", default=""); s.add_argument("--cli", default=find_cli()); s.add_argument("--timeout", type=int, default=150)
    sh = sub.add_parser("show"); sh.add_argument("key")
    a = ap.parse_args()
    if a.cmd == "fetch": return fetch(a.n, a.shard)
    if a.cmd == "score": return score(a.engine, a.cli, a.timeout)
    if a.cmd == "show":  return show(a.key)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
