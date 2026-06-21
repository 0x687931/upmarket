#!/usr/bin/env python3
"""IDL whole-page eval: convert real docs with upmarket-cli, score text vs Textract GT.

Three subcommands:

  fetch [N] [--shards A-B] Stream pixparse/idl-wds shard(s), cache NEW docs into $IDL_CORPUS
                          (default tests/corpus/idl/) as {key}.pdf + {key}.gt.txt. N caps the
                          count; N=0 (default) takes the WHOLE shard range — so the natural
                          Tier B unit is one shard: `fetch --shards 7-7`. Skips already-cached
                          keys, so it is resumable across runs.
  score --ai-engine granite|lfm2
                          Convert cached .pdf with the selected AI engine, write
                          {key}.<engine>.md, score word-similarity vs GT, and append
                          idl_results.jsonl. Skips docs already scored for that engine;
                          --sample N scores the same persisted subset for every engine.
  show KEY                Print GT | MD side by side for one doc (renders {key}.png on demand).

Caching means the fix->rebuild->rescore loop is fully offline and deterministic.

GT is AWS Textract OCR text (silver labels: plain lines, NO markdown structure). So the
NUMBER measures text-extraction / reading-order fidelity and is blind to table/heading
markup. Use it to catch regressions across all docs; use `show` + the .png to judge
STRUCTURE. For table structure specifically, use the TEDS harness (score.py).

ponytail: word-level difflib ratio, zero-dep. The score is a regression gauge, not truth
 — the page render + GT are the ground for judging fixes.
"""
import sys, json, tarfile, tempfile, subprocess, urllib.request, difflib, argparse, glob, os, random, re
from pathlib import Path
from statistics import mean
from concurrent.futures import ThreadPoolExecutor, as_completed

# IDL_CORPUS lets the Tier B sweep set live on an external drive; default is the in-git Tier A set.
CORPUS = Path(os.environ.get("IDL_CORPUS", "tests/corpus/idl"))
RESULTS = Path(os.environ.get(
    "IDL_RESULTS",
    str(CORPUS / "idl_results.jsonl") if os.environ.get("IDL_CORPUS")
    else "scripts/eval/idl_results.jsonl",
))
SHARD_URL = "https://huggingface.co/datasets/pixparse/idl-wds/resolve/main/idl-train-{:05d}.tar"
SAMPLE_SEED = 0
LOW_CONTENT_STATUS = "model-failure:low-content"


def hf_headers() -> dict:
    """Auth header from $HF_TOKEN or the standard huggingface-cli token file — lifts the
    anonymous download rate limit. Absent token = plain anonymous (still works, just slower)."""
    h = {"User-Agent": "idl-eval"}
    tok = os.environ.get("HF_TOKEN") or os.environ.get("HUGGING_FACE_HUB_TOKEN")
    if not tok:
        f = Path.home() / ".cache/huggingface/token"
        tok = f.read_text().strip() if f.exists() else ""
    if tok:
        h["Authorization"] = f"Bearer {tok}"
    return h


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


def download_resumable(url: str, dest: Path) -> int:
    """Download url to dest, resuming via HTTP Range after a dropped connection. HF throttles
    this download server-side (~MB/s per account, not per connection), so parallel ranges give
    no speedup — a single resumable stream is the right tool. A leftover partial from a killed
    run resumes on the next call."""
    head = urllib.request.urlopen(urllib.request.Request(url, method="HEAD", headers=hf_headers()))
    total = int(head.headers.get("Content-Length", 0)); head.close()
    stalls = 0
    while True:
        have = dest.stat().st_size if dest.exists() else 0
        if total and have >= total:
            return have
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={**hf_headers(), "Range": f"bytes={have}-"})) as resp, open(dest, "ab") as f:
                while chunk := resp.read(1 << 20):
                    f.write(chunk)
        except Exception as e:
            print(f"  resume from {(dest.stat().st_size if dest.exists() else 0)/1e6:.0f} MB after: {e}")
        got = dest.stat().st_size if dest.exists() else 0
        if not total:  # server hid the length; one pass is all we can verify
            return got
        if got <= have:  # no forward progress this pass
            stalls += 1
            if stalls >= 10:
                raise RuntimeError(f"stalled at {got}/{total} bytes: {url}")
        else:
            stalls = 0


def fetch(n: int, shards: range) -> int:
    CORPUS.mkdir(parents=True, exist_ok=True)
    done = 0
    for shard in shards:
        if n and done >= n:  # n=0 means take the whole shard range
            break
        url = SHARD_URL.format(shard)
        tar_path = CORPUS / f".shard-{shard:05d}.tar"  # temp on the same drive; partial = resumable
        print(f"downloading shard {shard} -> {tar_path.name}")
        size = download_resumable(url, tar_path)
        print(f"  got {size/1e6:.0f} MB, extracting")
        pend = {}
        with tarfile.open(tar_path, "r") as tar:  # local file: random access, no network during extract
            for m in tar:
                if not m.isfile():
                    continue
                key, _, ext = m.name.rpartition(".")
                if ext not in ("pdf", "json"):
                    continue  # skip tif/ocr
                if (CORPUS / f"{key}.pdf").exists():
                    continue  # already cached
                pend.setdefault(key, {})[ext] = tar.extractfile(m).read()
                s = pend.pop(key) if {"pdf", "json"} <= set(pend.get(key, {})) else None
                if not s:
                    continue
                (CORPUS / f"{key}.pdf").write_bytes(s["pdf"])
                (CORPUS / f"{key}.gt.txt").write_text(gt_text(json.loads(s["json"])), encoding="utf-8")
                # no png here — show() renders one on demand; saves a sips call per doc at scale.
                done += 1
                if done % 100 == 0:
                    print(f"  cached {done}" + (f"/{n}" if n else ""))
                if n and done >= n:
                    break
        tar_path.unlink()  # free the ~800 MB tar once extracted
    print(f"\ncached {done} new docs in {CORPUS}/ (pdf + gt.txt)")
    return 0


def scored_keys(eng: str) -> set:
    """Keys already scored for this engine — lets score resume over a large corpus."""
    done = set()
    if RESULTS.exists():
        for line in RESULTS.read_text(encoding="utf-8").splitlines():
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if r.get("engine") != eng:
                continue
            key = r.get("key")
            status = r.get("status")
            if status == LOW_CONTENT_STATUS:
                done.add(key)
            elif status == "ok":
                output = CORPUS / f"{key}.{eng}.md"
                if output.exists() and meaningful_word_count(
                    output.read_text(encoding="utf-8")
                ) == 0:
                    continue  # Legacy row: rerun once so it is logged as a model failure.
                done.add(key)
    return done


def meaningful_word_count(markdown: str) -> int:
    """Count extractable words after removing markup that carries no document text."""
    text = re.sub(r"<!--.*?-->", " ", markdown, flags=re.DOTALL)
    text = re.sub(r"!\[[^\]]*\]\([^)]*\)", " ", text)
    text = re.sub(r"</?[^>]+>", " ", text)
    return len(re.findall(r"[^\W_]+(?:['’-][^\W_]+)*", text, flags=re.UNICODE))


def sample_manifest_path(sample: int) -> Path:
    configured = os.environ.get("IDL_SAMPLE_MANIFEST")
    return Path(configured) if configured else CORPUS / f"idl_sample_{sample}.json"


def sampled_pdfs(pdfs: list[Path], sample: int) -> list[Path]:
    """Create or load one stable corpus sample shared by every engine."""
    if not sample or sample >= len(pdfs):
        return pdfs

    manifest_path = sample_manifest_path(sample)
    available = {pdf.stem: pdf for pdf in pdfs}
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        keys = manifest.get("keys")
        if (
            manifest.get("version") != 1
            or manifest.get("sample_size") != sample
            or not isinstance(keys, list)
            or len(keys) != sample
            or len(set(keys)) != sample
        ):
            raise ValueError(f"invalid sample manifest: {manifest_path}")
        missing = [key for key in keys if key not in available]
        if missing:
            raise ValueError(
                f"sample manifest references {len(missing)} missing document(s): {manifest_path}"
            )
        return [available[key] for key in keys]

    keys = sorted(random.Random(SAMPLE_SEED).sample(sorted(available), sample))
    manifest = {
        "version": 1,
        "sample_size": sample,
        "corpus_size": len(pdfs),
        "seed": SAMPLE_SEED,
        "keys": keys,
    }
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = manifest_path.with_suffix(manifest_path.suffix + ".tmp")
    temporary.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    temporary.replace(manifest_path)
    print(f"created shared sample manifest: {manifest_path}")
    return [available[key] for key in keys]


def score_one(
    pdf: Path,
    engine: str,
    ai_engine: str,
    eng: str,
    cli: str,
    timeout: int,
) -> dict:
    key = pdf.stem
    gt = (CORPUS / f"{key}.gt.txt").read_text(encoding="utf-8")
    out = CORPUS / f"{key}.{eng}.md"
    out.unlink(missing_ok=True)
    cmd = [cli, str(pdf), "-o", str(out), "--force"]
    if ai_engine:
        cmd += ["--ai-engine", ai_engine]
    elif engine:
        cmd.append(engine)
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        status = "ok" if r.returncode == 0 else f"err:{r.returncode}"
        error = "" if r.returncode == 0 else r.stderr.strip()[-500:]
    except subprocess.TimeoutExpired:
        status = "timeout"
        error = f"conversion exceeded {timeout}s"
    md = out.read_text(encoding="utf-8") if out.exists() else ""
    if status == "ok" and meaningful_word_count(md) == 0:
        status = LOW_CONTENT_STATUS
        error = "conversion produced only image placeholders or markup"
    sim = difflib.SequenceMatcher(None, gt.split(), md.split()).ratio()
    row = {"key": key, "engine": eng, "status": status,
           "gt_words": len(gt.split()), "md_words": len(md.split()), "sim": round(sim, 4)}
    if error:
        row["error"] = error
    return row


def score(
    engine: str,
    ai_engine: str,
    cli: str,
    timeout: int,
    sample: int,
    jobs: int,
) -> int:
    if not cli or not Path(cli).exists():
        print(f"upmarket-cli not found ({cli!r}). Build UpmarketCLI or set $UPMARKET_CLI.")
        return 1
    pdfs = sorted(CORPUS.glob("*.pdf"))
    if not pdfs:
        print(f"no docs in {CORPUS}/ — run `fetch` first.")
        return 1
    eng = ai_engine or engine.lstrip("-") or "auto"
    try:
        selected = sampled_pdfs(pdfs, sample)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"could not load sample manifest: {error}")
        return 1
    done = scored_keys(eng)
    todo = [p for p in selected if p.stem not in done]
    if not todo:
        print(f"all {len(selected)} selected docs already scored for engine={eng}")
        return 0
    completed_selected = len(selected) - len(todo)
    print(
        f"scoring {len(todo)} docs "
        f"(engine={eng}, jobs={jobs}, {completed_selected} selected docs already done)"
    )
    rows = []
    RESULTS.parent.mkdir(parents=True, exist_ok=True)
    with RESULTS.open("a", encoding="utf-8") as log, ThreadPoolExecutor(max_workers=jobs) as ex:
        futs = {
            ex.submit(score_one, p, engine, ai_engine, eng, cli, timeout): p
            for p in todo
        }
        for fut in as_completed(futs):  # subprocess work releases the GIL, so threads parallelise fine
            row = fut.result()
            rows.append(row)
            log.write(json.dumps(row) + "\n"); log.flush()
            print(f"{row['key']:<12} {row['status']:<25} gt={row['gt_words']:>5}w md={row['md_words']:>5}w  sim={row['sim']:.3f}")
    if rows:
        print(f"\nengine={eng}  n={len(rows)}  mean sim={mean(r['sim'] for r in rows):.3f}"
              f"  -> {RESULTS}  (inspect: idl_eval.py show <key>)")
    return 0


def show(key: str) -> int:
    gt = (CORPUS / f"{key}.gt.txt")
    mds = sorted(CORPUS.glob(f"{key}.*.md"))
    if not gt.exists():
        print(f"no GT for {key} in {CORPUS}/"); return 1
    png, pdf = CORPUS / f"{key}.png", CORPUS / f"{key}.pdf"
    if not png.exists() and pdf.exists():  # render lazily; fetch no longer emits png
        subprocess.run(["sips", "-s", "format", "png", str(pdf), "--out", str(png)], capture_output=True)
    print(f"=== {key} | page: {CORPUS}/{key}.png ===\n--- GT (Textract) ---")
    print(gt.read_text(encoding="utf-8"))
    for md in mds:
        print(f"\n--- MD ({md.suffixes[-2].lstrip('.')}) ---")
        print(md.read_text(encoding="utf-8"))
    return 0


def parse_shards(s: str) -> range:
    """'7' -> just shard 7; '0-200' -> shards 0..200 inclusive."""
    if "-" in s:
        a, b = s.split("-", 1)
        return range(int(a), int(b) + 1)
    return range(int(s), int(s) + 1)


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("fetch"); f.add_argument("n", nargs="?", type=int, default=0); f.add_argument("--shards", type=parse_shards, default=parse_shards("0"))
    s = sub.add_parser("score")
    s.add_argument("--engine", default="", help="Legacy routing flag such as --basic or --pro.")
    s.add_argument("--ai-engine", choices=("granite", "lfm2"), default="")
    s.add_argument("--cli", default=find_cli())
    s.add_argument("--timeout", type=int, default=600)
    s.add_argument("--sample", type=int, default=0)
    s.add_argument("--jobs", type=int)
    sh = sub.add_parser("show"); sh.add_argument("key")
    a = ap.parse_args()
    if a.cmd == "fetch": return fetch(a.n, a.shards)
    if a.cmd == "score":
        if a.ai_engine and a.engine:
            ap.error("--ai-engine cannot be combined with --engine")
        jobs = a.jobs if a.jobs is not None else (1 if a.ai_engine else (os.cpu_count() or 4))
        return score(a.engine, a.ai_engine, a.cli, a.timeout, a.sample, jobs)
    if a.cmd == "show":  return show(a.key)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
