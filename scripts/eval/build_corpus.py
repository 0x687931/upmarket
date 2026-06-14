#!/usr/bin/env python3
"""Build the Upmarket evaluation corpus: ONLY (document + ground-truth) pairs.

Scans raw source trees, copies each document and its matching ground truth into the
clean, version-controlled structure under tests/corpus/sources/, and writes
tests/corpus/manifest.json. Anything without a ground truth is ignored.

Layout produced:
    tests/corpus/sources/docling/documents/<format>/<doc>
    tests/corpus/sources/docling/groundtruth/<doc>.<gt-ext>
    tests/corpus/sources/pdfa/documents/<id>.pdf
    tests/corpus/sources/pdfa/groundtruth/<id>.expected.txt
    tests/corpus/manifest.json

Usage:
    build_corpus.py --docling-src <dir> [--pdfa-src <dir>]
"""
from __future__ import annotations
import argparse, json, os, shutil, sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CORPUS = REPO / "tests" / "corpus"
SOURCES = CORPUS / "sources"

GT_SUFFIXES = (".md", ".itxt", ".json", ".doctags.txt")


def _clean(dirpath: Path) -> None:
    if dirpath.exists():
        shutil.rmtree(dirpath)
    dirpath.mkdir(parents=True, exist_ok=True)


def build_docling(src: Path) -> list[dict]:
    """Pair each document under `src` with its ground truth in `src/groundtruth/`."""
    gt_root = src / "groundtruth"
    # Index ground-truth files by the source document filename they describe.
    gt_index: dict[str, Path] = {}
    for path in gt_root.rglob("*"):
        if not path.is_file():
            continue
        for suf in GT_SUFFIXES:
            if path.name.endswith(suf):
                doc_name = path.name[: -len(suf)]
                # Prefer .md ground truth when multiple exist for the same doc.
                if doc_name not in gt_index or suf == ".md":
                    gt_index[doc_name] = path
                break

    out_docs = SOURCES / "docling" / "documents"
    out_gt = SOURCES / "docling" / "groundtruth"
    _clean(out_docs); _clean(out_gt)

    entries: list[dict] = []
    for path in sorted(src.rglob("*")):
        if not path.is_file() or gt_root in path.parents:
            continue
        gt = gt_index.get(path.name)
        if gt is None:
            continue
        fmt = path.suffix.lstrip(".").lower() or "unknown"
        doc_dest = out_docs / fmt / path.name
        doc_dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, doc_dest)
        gt_dest = out_gt / gt.name
        shutil.copy2(gt, gt_dest)
        entries.append({
            "id": f"docling/{path.name}",
            "document": str(doc_dest.relative_to(REPO)),
            "ground_truth": str(gt_dest.relative_to(REPO)),
            "format": fmt,
            "source": "docling-project/docling (MIT)",
        })
    return entries


def build_pdfa(src: Path) -> list[dict]:
    """Pair <id>.pdf with <id>.expected.txt found anywhere under `src`."""
    out_docs = SOURCES / "pdfa" / "documents"
    out_gt = SOURCES / "pdfa" / "groundtruth"
    pdfs = {p.stem: p for p in src.rglob("*.pdf")}
    gts = {p.name[: -len(".expected.txt")]: p
           for p in src.rglob("*.expected.txt")}
    paired = sorted(set(pdfs) & set(gts))
    if not paired:
        return []
    _clean(out_docs); _clean(out_gt)
    entries: list[dict] = []
    for stem in paired:
        doc_dest = out_docs / f"{stem}.pdf"
        gt_dest = out_gt / f"{stem}.expected.txt"
        shutil.copy2(pdfs[stem], doc_dest)
        shutil.copy2(gts[stem], gt_dest)
        entries.append({
            "id": f"pdfa/{stem}",
            "document": str(doc_dest.relative_to(REPO)),
            "ground_truth": str(gt_dest.relative_to(REPO)),
            "format": "pdf",
            "source": "pixparse/pdfa-eng-wds (HuggingFace)",
        })
    return entries


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--docling-src", type=Path, help="Raw docling tests/data tree")
    ap.add_argument("--pdfa-src", type=Path, help="Extracted pdfa pdf+expected.txt tree")
    args = ap.parse_args()

    entries: list[dict] = []
    if args.docling_src and args.docling_src.exists():
        d = build_docling(args.docling_src)
        print(f"docling: {len(d)} document+ground-truth pairs")
        entries += d
    if args.pdfa_src and args.pdfa_src.exists():
        p = build_pdfa(args.pdfa_src)
        print(f"pdfa:    {len(p)} document+ground-truth pairs")
        entries += p

    if not entries:
        print("error: no document+ground-truth pairs found", file=sys.stderr)
        return 1

    by_fmt: dict[str, int] = {}
    for e in entries:
        by_fmt[e["format"]] = by_fmt.get(e["format"], 0) + 1

    manifest = {
        "version": 2,
        "description": "Upmarket CLI evaluation corpus — document + ground-truth pairs only",
        "pair_count": len(entries),
        "by_format": dict(sorted(by_fmt.items())),
        "documents": entries,
    }
    (CORPUS / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"\nwrote {CORPUS / 'manifest.json'} — {len(entries)} pairs {by_fmt}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
