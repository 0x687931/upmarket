"""
Upmarket benchmark comparison tool.
Generates a side-by-side comparison of all pipelines across all corpus documents.
Run after benchmark_scorer.py for each pipeline.

Usage:
    python3 scripts/benchmark_compare.py \
        --fast /tmp/bench_fast_full.txt \
        --enhanced /tmp/bench_enhanced_full.txt
"""

import re
import sys
import argparse
from pathlib import Path


def parse_results(path: str) -> dict:
    """Parse benchmark output into {doc_id: score} dict."""
    results = {}
    with open(path) as f:
        for line in f:
            # Match: "  docling_xxx  [GT] ✓  93%  (0.5s)"
            m = re.match(r'\s+(\S+)\s+\[..\]\s+[✓⚠✗]\s+(\d+)%', line)
            if m:
                results[m.group(1)] = int(m.group(2))
            # Match errors
            m2 = re.match(r'\s+(\S+)\s+\[..\]\s+✗\s+ERROR:', line)
            if m2:
                results[m2.group(1)] = -1  # -1 = error
            m3 = re.match(r'\s+(\S+)\s+\[..\]\s+✗\s+TIMEOUT', line)
            if m3:
                results[m3.group(1)] = -2  # -2 = timeout
    return results


def compare(pipelines: dict[str, dict]) -> None:
    """Print side-by-side comparison table."""
    all_docs = sorted(set(doc for p in pipelines.values() for doc in p))
    names = list(pipelines.keys())

    # Header
    col_w = 42
    header = f"{'Document':<{col_w}}" + "".join(f"  {n:>10}" for n in names) + "   Best"
    print(header)
    print("-" * (col_w + 14 * len(names) + 8))

    by_category: dict[str, list] = {}
    for doc in all_docs:
        # Get category from doc name heuristic
        cat = _infer_category(doc)
        if cat not in by_category:
            by_category[cat] = []
        by_category[cat].append(doc)

    for cat in sorted(by_category):
        print(f"\n  [{cat}]")
        cat_scores: dict[str, list[int]] = {n: [] for n in names}

        for doc in by_category[cat]:
            short = doc.replace('docling_', '')[:col_w-1]
            scores = {n: pipelines[n].get(doc) for n in names}
            row = f"  {short:<{col_w-2}}"
            valid = {n: s for n, s in scores.items() if s is not None and s >= 0}

            for n in names:
                s = scores.get(n)
                if s is None:
                    row += f"  {'—':>10}"
                elif s == -1:
                    row += f"  {'ERROR':>10}"
                elif s == -2:
                    row += f"  {'TIMEOUT':>10}"
                else:
                    row += f"  {s:>9}%"
                    cat_scores[n].append(s)

            best = max(valid.values()) if valid else None
            best_name = [n for n, s in valid.items() if s == best][0] if best else None
            row += f"  {best_name or '—':>6}" if best else ""
            print(row)

        # Category averages
        avgs = {n: (sum(cat_scores[n]) // len(cat_scores[n])) if cat_scores[n] else 0
                for n in names}
        avg_row = f"  {'  AVG':<{col_w-2}}"
        for n in names:
            avg_row += f"  {avgs[n]:>9}%"
        print(avg_row)

    # Overall
    print("\n" + "=" * (col_w + 14 * len(names) + 8))
    all_scores = {n: [s for s in pipelines[n].values() if s >= 0] for n in names}
    overall_row = f"  {'OVERALL':<{col_w-2}}"
    for n in names:
        avg = sum(all_scores[n]) // len(all_scores[n]) if all_scores[n] else 0
        overall_row += f"  {avg:>9}%"
    print(overall_row)

    errors = {n: sum(1 for s in pipelines[n].values() if s == -1) for n in names}
    timeouts = {n: sum(1 for s in pipelines[n].values() if s == -2) for n in names}
    print(f"\n  Errors:   " + "  ".join(f"{errors[n]:>10}" for n in names))
    print(f"  Timeouts: " + "  ".join(f"{timeouts[n]:>10}" for n in names))


def _infer_category(doc: str) -> str:
    name = doc.replace('docling_', '').lower()
    if any(x in name for x in ['arxiv', '2203', '2206', '2305', 'acl', 'llm', 'bert', 'gpt']):
        return 'pdf/academic'
    if any(x in name for x in ['handbook', 'redp', 'ibm', 'normal', 'multi_page', 'picture']):
        return 'pdf/business'
    if any(x in name for x in ['right_to_left', 'rtl', 'arabic', 'hebrew']):
        return 'pdf/rtl'
    if any(x in name for x in ['code', 'formula', 'equation', 'math', 'omml']):
        return 'pdf/technical'
    if name.startswith('docx') or any(x in name for x in ['word', 'lorem', 'unit_test', 'tablecell', 'textbox']):
        return 'office/docx'
    if 'powerpoint' in name or 'pptx' in name:
        return 'office/pptx'
    if 'xlsx' in name or 'excel' in name:
        return 'office/xlsx'
    if 'csv' in name:
        return 'data/csv'
    if 'html' in name or 'hyperlink' in name or 'example_0' in name:
        return 'web/html'
    if any(x in name for x in ['audio', 'wav', 'mp3', 'flac', 'm4a', 'silent']):
        return 'audio'
    if any(x in name for x in ['video', 'mp4', 'mov', 'avi']):
        return 'video'
    if any(x in name for x in ['png', 'tif', 'webp', 'img', 'ModalNet', 'bars', 'sizes',
                                 'scatter', 'SFNet', 'pca', 'fp8', 'rolling', 'swa', 'overlap']):
        return 'image'
    if 'vtt' in name or 'webvtt' in name:
        return 'webvtt'
    if any(x in name for x in ['xml', 'ipa', 'ipg', 'xbrl', 'grve', 'mlac', 'uspto']):
        return 'data/xml'
    if 'asciidoc' in name or 'test_0' in name:
        return 'asciidoc'
    return 'other'


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--fast',     default='/tmp/bench_fast_full.txt')
    parser.add_argument('--enhanced', default='/tmp/bench_enhanced_full.txt')
    args = parser.parse_args()

    pipelines = {}
    if Path(args.fast).exists():
        pipelines['fast'] = parse_results(args.fast)
        print(f"Fast: {len(pipelines['fast'])} results")
    if Path(args.enhanced).exists():
        pipelines['enhanced'] = parse_results(args.enhanced)
        print(f"Enhanced: {len(pipelines['enhanced'])} results")

    if not pipelines:
        print("No results found. Run benchmark_scorer.py first.")
        sys.exit(1)

    print()
    compare(pipelines)
