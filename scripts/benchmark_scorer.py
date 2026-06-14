"""
Upmarket benchmark scorer.
Converts corpus documents and scores against ground truth (.expected.md).
"""

import argparse
import json
import os
import platform
import re
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

PATHWAYS = {
    "python-fast-pdfium": {
        "pipeline": "fast",
        "valid_categories": {"pdf"},
        "release_status": "shipping",
    },
    "python-fast-markitdown": {
        "pipeline": "fast",
        "valid_categories": {"asciidoc", "audio", "csv", "docx", "html", "image", "pptx", "webvtt", "xlsx", "xml"},
        "valid_formats": {"asciidoc", "csv", "docx", "epub", "html", "jpeg", "jpg", "json", "m4a", "md", "mp3", "png", "pptx", "wav", "webvtt", "xlsx", "xml", "zip"},
        "release_status": "shipping",
    },
    "python-enhanced-docling": {
        "pipeline": "enhanced",
        "valid_categories": {"asciidoc", "csv", "docx", "html", "image", "pdf", "pptx", "webvtt", "xlsx", "xml"},
        "release_status": "shipping",
    },
    "python-ai-docling": {
        "pipeline": "ai",
        "valid_categories": {"image", "pdf"},
        "release_status": "shipping",
    },
    "internal-reference-pymupdf": {
        "pipeline": "pymupdf-reference",
        "valid_categories": {"pdf"},
        "release_status": "internal-reference-only",
    },
    "internal-reference-poppler": {
        "pipeline": "poppler-reference",
        "valid_categories": {"pdf"},
        "release_status": "internal-reference-only",
    },
    "internal-reference-rapidocr": {
        "pipeline": "rapidocr-reference",
        "valid_categories": {"image", "pdf"},
        "release_status": "internal-reference-only",
    },
    "internal-reference-paddleocr": {
        "pipeline": "paddleocr-reference",
        "valid_categories": {"image", "pdf"},
        "release_status": "internal-reference-only",
    },
}

_RAPIDOCR_ENGINE = None
_PADDLEOCR_ENGINE = None
ISOLATED_REFERENCE_PATHWAYS = {"internal-reference-paddleocr"}


# ── Scoring ───────────────────────────────────────────────────────────────────

@dataclass
class DocScore:
    doc_id: str
    category: str
    file: str = ""
    bucket: str | None = None
    heading_recall: float = 0.0
    table_accuracy: float = 0.0
    content_completeness: float = 0.0
    markdown_valid: bool = True
    artifacts_found: int = 0
    elapsed_seconds: float = 0.0
    elapsed_runs_seconds: list[float] = field(default_factory=list)
    error: str | None = None
    expected_blocked: bool = False
    blocked_reason: str | None = None

    @property
    def overall(self) -> float:
        if self.error or self.expected_blocked:
            return 0.0
        w = [
            (self.heading_recall,       0.30),
            (self.table_accuracy,       0.25),
            (self.content_completeness, 0.30),
            (1.0 if self.markdown_valid else 0.0, 0.10),
            (max(0.0, 1.0 - self.artifacts_found / 10), 0.05),
        ]
        return sum(score * weight for score, weight in w)


def manifest_format(meta: dict) -> str:
    """Grouping key for a manifest document.

    The Document+GroundTruth corpus keys documents by `format`; older manifests
    used `category`. Prefer `format`, fall back to `category` for compatibility.
    """
    return meta.get("format") or meta.get("category", "unknown")


def resolve_corpus_path(corpus_dir: Path, rel: str) -> Path:
    """Resolve a manifest path. Current manifests store repo-root-relative paths
    (e.g. tests/corpus/sources/...); older ones were relative to the corpus dir."""
    candidate = Path(rel)
    if candidate.is_absolute():
        return candidate
    repo_relative = Path.cwd() / candidate
    if repo_relative.exists():
        return repo_relative
    return corpus_dir / candidate


def score_document(output_md: str, meta: dict, ground_truth_md: str | None = None) -> DocScore:
    doc_id = meta.get("id", "unknown")
    category = manifest_format(meta)
    score = DocScore(doc_id=doc_id, category=category)

    # If ground truth is available, use it as the source of truth
    if ground_truth_md:
        return score_against_ground_truth(output_md, ground_truth_md, doc_id, category)

    # Fallback: score against expected_features metadata
    features = meta.get("expected_features", {})

    expected_headings = features.get("headings", [])
    if expected_headings:
        found = extract_headings(output_md)
        matched = sum(
            1 for h in expected_headings
            if any(h.lower() in f.lower() for f in found)
        )
        score.heading_recall = matched / len(expected_headings)
    else:
        score.heading_recall = 1.0

    expected_tables = features.get("tables", 0)
    found_tables = count_md_tables(output_md)
    if expected_tables == 0:
        score.table_accuracy = 1.0 if found_tables == 0 else 0.8
    else:
        ratio = found_tables / expected_tables
        score.table_accuracy = min(1.0, ratio) if ratio <= 1.5 else max(0.0, 2.0 - ratio)

    expected_words = features.get("estimated_words", 0)
    if expected_words > 0:
        actual_words = len(output_md.split())
        ratio = actual_words / expected_words
        score.content_completeness = 1.0 if 0.8 <= ratio <= 1.2 else (
            0.7 if 0.6 <= ratio <= 1.4 else max(0.0, 1.0 - abs(ratio - 1.0))
        )
    else:
        score.content_completeness = 1.0 if len(output_md) > 100 else 0.0

    score.markdown_valid = validate_markdown(output_md)
    score.artifacts_found = count_artifacts(output_md)
    return score


def score_against_ground_truth(output_md: str, ground_truth_md: str, doc_id: str, category: str) -> DocScore:
    """Score output against a known-good ground truth Markdown file."""
    score = DocScore(doc_id=doc_id, category=category)

    gt_headings = extract_headings(ground_truth_md)
    out_headings = extract_headings(output_md)

    # Heading recall: what fraction of GT headings appear in output
    if gt_headings:
        matched = sum(
            1 for h in gt_headings
            if any(h.lower()[:30] in f.lower() for f in out_headings)
        )
        score.heading_recall = matched / len(gt_headings)
    else:
        score.heading_recall = 1.0 if not out_headings else 0.8

    # Table accuracy
    gt_tables = count_md_tables(ground_truth_md)
    out_tables = count_md_tables(output_md)
    if gt_tables == 0:
        score.table_accuracy = 1.0 if out_tables == 0 else 0.7
    else:
        ratio = out_tables / gt_tables
        score.table_accuracy = min(1.0, ratio) if ratio <= 1.3 else max(0.0, 2.0 - ratio)

    # Content completeness: word count vs ground truth
    gt_words = len(ground_truth_md.split())
    out_words = len(output_md.split())
    if gt_words > 0:
        ratio = out_words / gt_words
        score.content_completeness = 1.0 if 0.75 <= ratio <= 1.3 else (
            0.7 if 0.5 <= ratio <= 1.5 else max(0.0, 1.0 - abs(ratio - 1.0))
        )
    else:
        score.content_completeness = 1.0

    # Character-level similarity for key sections (BLEU-like)
    score.content_completeness = min(
        score.content_completeness,
        text_similarity(output_md[:2000], ground_truth_md[:2000])
    )

    score.markdown_valid = validate_markdown(output_md)
    score.artifacts_found = count_artifacts(output_md)
    return score


def text_similarity(a: str, b: str, n: int = 3) -> float:
    """Character n-gram overlap (simplified BLEU) between two texts."""
    def ngrams(text, n):
        text = re.sub(r'\s+', ' ', text.lower())
        return {text[i:i+n] for i in range(len(text) - n + 1)}
    if not a or not b:
        return 0.0
    a_ng, b_ng = ngrams(a, n), ngrams(b, n)
    if not a_ng:
        return 0.0
    return len(a_ng & b_ng) / len(a_ng)


def extract_headings(md: str) -> list[str]:
    return [
        re.sub(r'^#+\s*', '', line).strip()
        for line in md.splitlines()
        if line.strip().startswith('#')
    ]


def count_md_tables(md: str) -> int:
    # Count table separator rows (| --- | --- |)
    return len(re.findall(r'^\|[\s\-|:]+\|', md, re.MULTILINE))


def validate_markdown(md: str) -> bool:
    # Check for obviously broken Markdown
    lines = md.splitlines()
    in_table = False
    for line in lines:
        stripped = line.strip()
        # Unclosed bold/italic
        if stripped.count('**') % 2 != 0:
            return False
        # Table row without closing pipe
        if stripped.startswith('|') and not stripped.endswith('|'):
            return False
    return True


def count_artifacts(md: str) -> int:
    """Count PDF extraction artifacts that should have been cleaned."""
    artifacts = 0
    # Page numbers floating in text
    artifacts += len(re.findall(r'\n\d{1,3}\n', md))
    # Soft hyphens
    artifacts += md.count('\xad')
    # Replacement chars
    artifacts += md.count('') + md.count('')
    # Ligature chars not cleaned
    for lig in ['ﬁ', 'ﬂ', 'ﬃ', 'ﬄ', 'ﬀ']:
        artifacts += md.count(lig)
    return artifacts


def is_expected_blocked_error(message: str | None) -> tuple[bool, str | None]:
    """Classify missing user-supplied input as blocked, not converter failure."""
    if not message:
        return False, None
    lowered = message.lower()
    if "password" in lowered and ("protected" in lowered or "required" in lowered or "encrypted" in lowered):
        return True, "password_required"
    return False, None


# ── Conversion ────────────────────────────────────────────────────────────────

def convert_document(doc_path: Path, pipeline: str, pathway: str | None = None) -> tuple[str, float]:
    """Convert a document and return (markdown, elapsed_seconds)."""
    import sys

    if pathway == "internal-reference-pymupdf":
        return _convert_via_pymupdf_reference(doc_path)
    if pathway == "internal-reference-poppler":
        return _convert_via_poppler_reference(doc_path)
    if pathway == "internal-reference-rapidocr":
        return _convert_via_rapidocr_reference(doc_path)
    if pathway == "internal-reference-paddleocr":
        return _convert_via_paddleocr_reference(doc_path)

    if pipeline in ("enhanced", "ai"):
        # Use venv directly — has Docling + cached models
        return _convert_via_venv(doc_path, pipeline)
    else:
        # Fast path — use bundled framework
        site = Path(__file__).parent.parent / 'Upmarket/Python/Python.xcframework/macos-arm64_x86_64/Python.framework/Versions/3.12/lib/python3.12/site-packages'
        if str(site) not in sys.path:
            sys.path.insert(0, str(site))
        from docling_bridge.converter import convert
        start = time.time()
        result = convert(str(doc_path), {"use_enhanced": False, "use_ai": False})
        elapsed = time.time() - start
        if result.get("success"):
            return result["markdown"], elapsed
        raise RuntimeError(result.get("error", "Unknown error"))


def _convert_via_pymupdf_reference(doc_path: Path) -> tuple[str, float]:
    """Developer-only PDF reference pathway. This must never ship in the app."""
    start = time.time()
    try:
        import fitz  # type: ignore
    except Exception as exc:
        raise RuntimeError("PyMuPDF reference package is not installed in this developer environment") from exc

    parts: list[str] = []
    with fitz.open(str(doc_path)) as document:
        for index, page in enumerate(document, start=1):
            text = page.get_text("text").strip()
            if text:
                parts.append(f"## Page {index}\n\n{text}")
    return "\n\n".join(parts), time.time() - start


def _convert_via_poppler_reference(doc_path: Path) -> tuple[str, float]:
    """Developer-only Poppler reference pathway. This must never ship in the app."""
    import shutil
    import subprocess

    pdftotext = shutil.which("pdftotext")
    if not pdftotext:
        raise RuntimeError("Poppler pdftotext is not installed in this developer environment")
    start = time.time()
    proc = subprocess.run(
        [pdftotext, "-layout", str(doc_path), "-"],
        capture_output=True,
        text=True,
        timeout=120,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr[-500:] if proc.stderr else "Poppler pdftotext failed")
    return proc.stdout.strip(), time.time() - start


def _convert_via_rapidocr_reference(doc_path: Path) -> tuple[str, float]:
    """Developer-only RapidOCR reference pathway. This must never ship in the app."""
    global _RAPIDOCR_ENGINE
    start = time.time()
    if _RAPIDOCR_ENGINE is None:
        try:
            from rapidocr import RapidOCR  # type: ignore
        except Exception as exc:
            raise RuntimeError("RapidOCR reference package is not installed in this developer environment") from exc
        _RAPIDOCR_ENGINE = RapidOCR()

    pages = _ocr_input_images(doc_path)
    parts = []
    for index, image_path in enumerate(pages, start=1):
        result = _RAPIDOCR_ENGINE(str(image_path))
        text = _rapidocr_text(result)
        if text:
            parts.append(f"## Page {index}\n\n{text}")
    return "\n\n".join(parts), time.time() - start


def _convert_via_paddleocr_reference(doc_path: Path) -> tuple[str, float]:
    """Developer-only PaddleOCR reference pathway. This must never ship in the app."""
    global _PADDLEOCR_ENGINE
    start = time.time()
    if _PADDLEOCR_ENGINE is None:
        try:
            from paddleocr import PaddleOCR  # type: ignore
        except Exception as exc:
            raise RuntimeError("PaddleOCR reference package is not installed in this developer environment") from exc

        _PADDLEOCR_ENGINE = PaddleOCR(
            lang="en",
            use_doc_orientation_classify=False,
            use_doc_unwarping=False,
            use_textline_orientation=False,
        )
    pages = _ocr_input_images(doc_path)
    parts = []
    for index, image_path in enumerate(pages, start=1):
        result = _PADDLEOCR_ENGINE.predict(str(image_path))
        text = _paddleocr_text(result)
        if text:
            parts.append(f"## Page {index}\n\n{text}")
    return "\n\n".join(parts), time.time() - start


def _ocr_input_images(doc_path: Path) -> list[Path]:
    if doc_path.suffix.lower() != ".pdf":
        return [doc_path]

    import tempfile

    try:
        import pypdfium2 as pdfium  # type: ignore
    except Exception as exc:
        raise RuntimeError("pypdfium2 is required to render PDFs for OCR reference pathways") from exc

    out_dir = Path(tempfile.mkdtemp(prefix="upmarket-ocr-reference-"))
    images: list[Path] = []
    document = pdfium.PdfDocument(str(doc_path))
    try:
        for index in range(len(document)):
            page = document[index]
            bitmap = page.render(scale=1.5)
            image = bitmap.to_pil()
            image.thumbnail((1600, 1600))
            image_path = out_dir / f"page-{index + 1}.png"
            image.save(image_path)
            images.append(image_path)
    finally:
        document.close()
    return images


def _rapidocr_text(result) -> str:
    if hasattr(result, "txts"):
        return "\n".join(str(text) for text in (result.txts or []) if text)
    if hasattr(result, "to_markdown"):
        markdown = result.to_markdown()
        if markdown:
            return str(markdown)
    lines = []
    for item in result or []:
        if isinstance(item, (list, tuple)) and len(item) >= 2:
            text = item[1]
            if isinstance(text, str):
                lines.append(text)
            elif isinstance(text, (list, tuple)) and text:
                lines.append(str(text[0]))
    return "\n".join(lines)


def _paddleocr_text(result) -> str:
    lines = []
    for page in result or []:
        if isinstance(page, dict):
            rec_texts = page.get("rec_texts") or page.get("text") or []
            if isinstance(rec_texts, str):
                lines.append(rec_texts)
            else:
                lines.extend(str(text) for text in rec_texts if text)
            continue
        if hasattr(page, "json"):
            data = page.json
            if isinstance(data, dict):
                rec_texts = data.get("rec_texts") or []
                lines.extend(str(text) for text in rec_texts if text)
            continue
        for item in page or []:
            if isinstance(item, (list, tuple)) and len(item) >= 2:
                text_info = item[1]
                if isinstance(text_info, (list, tuple)) and text_info:
                    lines.append(str(text_info[0]))
                elif isinstance(text_info, str):
                    lines.append(text_info)
    return "\n".join(lines)


def _convert_via_venv(doc_path: Path, pipeline: str) -> tuple[str, float]:
    """Run Enhanced/AI conversion in-process so model-backed benchmarks stay warm."""
    root = Path(__file__).parent.parent
    source_bridge = root / "UpmarketPython"
    value = str(source_bridge)
    if value not in sys.path:
        sys.path.insert(0, value)

    from docling_bridge.converter import convert

    opts = {"use_enhanced": pipeline in ("enhanced", "ai"), "use_ai": pipeline == "ai"}
    start = time.time()
    result = convert(str(doc_path), opts)
    elapsed = time.time() - start
    if result.get("success"):
        return result["markdown"], result.get("elapsed", elapsed)
    raise RuntimeError(result.get("error", "Unknown error"))


def convert_document_isolated(doc_path: Path, pipeline: str, pathway: str, timeout_seconds: int) -> tuple[str, float]:
    """Run crash-prone benchmark-only converters out of process."""
    import subprocess

    proc = subprocess.run(
        [
            sys.executable,
            str(Path(__file__).resolve()),
            "--convert-one",
            str(doc_path),
            "--pipeline",
            pipeline,
            "--pathway",
            pathway,
        ],
        capture_output=True,
        text=True,
        timeout=timeout_seconds,
    )
    lines = [line for line in proc.stdout.splitlines() if line.startswith("{")]
    if proc.returncode != 0:
        detail = proc.stderr.strip() or proc.stdout.strip() or f"worker exited {proc.returncode}"
        raise RuntimeError(detail[-500:])
    if not lines:
        raise RuntimeError("isolated converter produced no JSON result")
    result = json.loads(lines[-1])
    if not result.get("success"):
        raise RuntimeError(result.get("error", "isolated converter failed"))
    return result.get("markdown", ""), float(result.get("elapsed_seconds", 0.0))


# ── Runner ────────────────────────────────────────────────────────────────────

def benchmark_host(compute_mode: str) -> dict:
    host = {
        "system": platform.system(),
        "release": platform.release(),
        "machine": platform.machine(),
        "processor": platform.processor(),
        "mac_version": platform.mac_ver()[0],
        "requested_compute_mode": compute_mode,
    }
    if platform.system() == "Darwin":
        try:
            import subprocess

            proc = subprocess.run(
                ["sysctl", "-n", "machdep.cpu.brand_string"],
                capture_output=True,
                text=True,
                timeout=2,
            )
            if proc.returncode == 0:
                host["cpu_brand"] = proc.stdout.strip()
        except Exception:
            pass
    return host


def run_benchmark(
    corpus_dir: Path,
    pipeline: str,
    pathway: str,
    category_filter: str,
    bucket_filter: str,
    fail_below: int,
    repeat_count: int,
    compute_mode: str,
    json_output: Path | None = None
) -> int:
    scores: list[DocScore] = []
    manifest_path = corpus_dir / "manifest.json"
    corpus_root = str(corpus_dir.resolve())
    existing_roots = os.environ.get("UPMARKET_ALLOWED_INPUT_ROOTS")
    os.environ["UPMARKET_ALLOWED_INPUT_ROOTS"] = (
        corpus_root if not existing_roots else existing_roots + os.pathsep + corpus_root
    )
    os.environ.setdefault("TMPDIR", str((Path.cwd() / "build" / "benchmark-tmp").resolve()))
    os.environ["UPMARKET_BENCHMARK_COMPUTE_MODE"] = compute_mode
    benchmark_cache = Path.cwd() / "reports" / "benchmark-cache"
    benchmark_cache.mkdir(parents=True, exist_ok=True)
    os.environ.setdefault("UPMARKET_MODELS_DIR", str((benchmark_cache / "upmarket-models").resolve()))
    os.environ.setdefault("PADDLE_PDX_CACHE_HOME", str((benchmark_cache / "paddlex").resolve()))
    os.environ.setdefault("PADDLE_HOME", str((benchmark_cache / "paddle").resolve()))
    os.environ.setdefault("HF_HOME", str((benchmark_cache / "huggingface").resolve()))
    os.environ.setdefault("MODELSCOPE_CACHE", str((benchmark_cache / "modelscope").resolve()))
    os.environ.setdefault("XDG_CACHE_HOME", str((benchmark_cache / "xdg").resolve()))
    os.environ.setdefault("PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK", "True")

    if not manifest_path.exists():
        print(f"No manifest.json found in {corpus_dir}")
        print("Create corpus first: see docs/CORPUS_STRATEGY.md")
        return 0

    manifest = json.loads(manifest_path.read_text())
    docs = manifest.get("documents", [])
    bucket_labels = load_bucket_labels()
    for doc in docs:
        if doc.get("id") in bucket_labels:
            doc["bucket"] = bucket_labels[doc["id"]]

    selected_pathway = None
    if pathway:
        selected_pathway = PATHWAYS.get(pathway)
        if selected_pathway is None:
            print(f"Unknown pathway: {pathway}")
            print("Known pathways: " + ", ".join(sorted(PATHWAYS)))
            return 1
        pipeline = selected_pathway["pipeline"]
        valid_categories = selected_pathway["valid_categories"]
        valid_formats = selected_pathway.get("valid_formats")
        docs = [d for d in docs if d.get("category") in valid_categories]
        if valid_formats:
            docs = [d for d in docs if d.get("format") in valid_formats]

    if category_filter:
        docs = [d for d in docs if manifest_format(d).startswith(category_filter)]
    if bucket_filter:
        docs = [d for d in docs if d.get("bucket") == bucket_filter]

    if not docs:
        filters = []
        if category_filter:
            filters.append(f"category: {category_filter}")
        if bucket_filter:
            filters.append(f"bucket: {bucket_filter}")
        print(f"No documents found{' for ' + ', '.join(filters) if filters else ''}")
        return 0

    repeat_count = max(1, repeat_count)
    label = f"pathway: {pathway}" if pathway else f"pipeline: {pipeline or 'auto'}"
    repeat_label = f" | repeats: {repeat_count}" if repeat_count > 1 else ""
    bucket_label = f" | bucket: {bucket_filter}" if bucket_filter else ""
    print(f"Running {len(docs)} documents | {label}{repeat_label}{bucket_label} | compute: {compute_mode}\n")

    for doc_meta in docs:
        doc_id = doc_meta["id"]
        category = manifest_format(doc_meta)
        # Manifest stores the source under `document` (older manifests used `file`).
        doc_rel = doc_meta.get("document") or doc_meta.get("file", "")
        file_path = resolve_corpus_path(corpus_dir, doc_rel)
        if not file_path.exists():
            print(f"  SKIP {doc_id} — file not found")
            continue

        print(f"  {doc_id:<40}", end="", flush=True)

        # Load ground truth if available
        ground_truth_md = None
        gt_key = doc_meta.get("ground_truth")
        if gt_key:
            gt_path = resolve_corpus_path(corpus_dir, gt_key)
            if gt_path.exists():
                ground_truth_md = gt_path.read_text(encoding="utf-8", errors="replace")

        try:
            import signal

            elapsed_runs = []
            markdown = ""
            timeout_seconds = 300 if pipeline == "ai" else (120 if pipeline == "enhanced" else 30)
            if pathway in ISOLATED_REFERENCE_PATHWAYS:
                for _ in range(repeat_count):
                    markdown, elapsed = convert_document_isolated(
                        file_path,
                        pipeline or "fast",
                        pathway,
                        timeout_seconds=45,
                    )
                    elapsed_runs.append(elapsed)
            else:
                def _timeout_handler(signum, frame):
                    raise TimeoutError(f"Conversion timed out after {timeout_seconds}s")

                signal.signal(signal.SIGALRM, _timeout_handler)
                signal.alarm(timeout_seconds)
                try:
                    for _ in range(repeat_count):
                        markdown, elapsed = convert_document(file_path, pipeline or "fast", pathway or None)
                        elapsed_runs.append(elapsed)
                finally:
                    signal.alarm(0)

            score = score_document(markdown, doc_meta, ground_truth_md)
            score.file = doc_meta.get("document", doc_meta.get("file", ""))
            score.bucket = doc_meta.get("bucket")
            score.elapsed_runs_seconds = elapsed_runs
            score.elapsed_seconds = sum(elapsed_runs) / len(elapsed_runs)
            scores.append(score)
            gt_indicator = "GT" if ground_truth_md else "  "
            status = "✓" if score.overall >= 0.8 else "⚠" if score.overall >= 0.6 else "✗"
            print(f"[{gt_indicator}] {status}  {score.overall*100:.0f}%  ({score.elapsed_seconds:.3f}s avg)")
        except TimeoutError as exc:
            score = DocScore(doc_id=doc_id, category=category, file=doc_meta.get("document", doc_meta.get("file", "")), error=str(exc) or "Timed out")
            score.bucket = doc_meta.get("bucket")
            scores.append(score)
            print(f"[  ] ✗  TIMEOUT ({score.error})")
        except Exception as e:
            message = str(e)
            expected_blocked, reason = is_expected_blocked_error(message)
            score = DocScore(
                doc_id=doc_id,
                category=category,
                file=doc_meta.get("document", doc_meta.get("file", "")),
                error=None if expected_blocked else message,
                expected_blocked=expected_blocked,
                blocked_reason=reason,
            )
            score.bucket = doc_meta.get("bucket")
            scores.append(score)
            if expected_blocked:
                print(f"[  ] ⏸  BLOCKED: {reason}")
            else:
                print(f"[  ] ✗  ERROR: {e}")

    # Summary table
    print("\n" + "═" * 65)
    print_summary(scores)

    scored = [s for s in scores if not s.expected_blocked]
    overall_avg = sum(s.overall for s in scored) / len(scored) if scored else 0
    elapsed_avg = sum(s.elapsed_seconds for s in scored) / len(scored) if scored else 0
    blocked_count = sum(1 for s in scores if s.expected_blocked)
    blocked_label = f", {blocked_count} expected blocked" if blocked_count else ""
    print(f"\nOverall: {overall_avg*100:.1f}%  ({len(scored)}/{len(scores)} scored documents{blocked_label}, {elapsed_avg:.3f}s avg/document)")

    if json_output:
        write_json_report(json_output, pipeline or "fast", pathway or None, scores, corpus_dir, category_filter, bucket_filter, repeat_count, compute_mode)
        print(f"JSON report: {json_output}")

    if fail_below > 0 and overall_avg * 100 < fail_below:
        print(f"\nFAIL: score {overall_avg*100:.1f}% below threshold {fail_below}%")
        return 1

    return 0


def load_bucket_labels(path: Path = Path("docs/release/corpus_bucket_classification.json")) -> dict[str, str]:
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    return {
        doc["id"]: doc["bucket"]
        for doc in data.get("documents", [])
        if doc.get("id") and doc.get("bucket")
    }


def print_summary(scores: list[DocScore]):
    # Group by category
    by_category: dict[str, list[DocScore]] = {}
    for s in scores:
        cat = s.category.split("/")[0]
        by_category.setdefault(cat, []).append(s)

    header = f"{'Category':<25} {'Docs':>4} {'Headings':>8} {'Tables':>7} {'Content':>8} {'Overall':>8} {'Avg Sec':>8}"
    print(header)
    print("-" * 65)

    for cat, cat_scores in sorted(by_category.items()):
        valid = [s for s in cat_scores if not s.error and not s.expected_blocked]
        if not valid:
            continue
        avg = lambda f: sum(getattr(s, f) for s in valid) / len(valid)
        print(
            f"{cat:<25} {len(cat_scores):>4} "
            f"{avg('heading_recall')*100:>7.0f}% "
            f"{avg('table_accuracy')*100:>6.0f}% "
            f"{avg('content_completeness')*100:>7.0f}% "
            f"{sum(s.overall for s in valid)/len(valid)*100:>7.0f}% "
            f"{sum(s.elapsed_seconds for s in valid)/len(valid):>7.3f}"
        )


def write_json_report(path: Path, pipeline: str, pathway: str | None, scores: list[DocScore], corpus_dir: Path, category_filter: str, bucket_filter: str, repeat_count: int, compute_mode: str) -> None:
    by_category: dict[str, list[DocScore]] = {}
    for score in scores:
        category = score.category.split("/")[0]
        by_category.setdefault(category, []).append(score)

    categories = {}
    for category, category_scores in sorted(by_category.items()):
        scored_category = [score for score in category_scores if not score.expected_blocked]
        categories[category] = {
            "document_count": len(category_scores),
            "scored_document_count": len(scored_category),
            "overall_percent": round(sum(score.overall for score in scored_category) / len(scored_category) * 100, 1) if scored_category else 0.0,
            "avg_elapsed_seconds": round(sum(score.elapsed_seconds for score in scored_category) / len(scored_category), 4) if scored_category else 0.0,
            "total_elapsed_seconds": round(sum(score.elapsed_seconds for score in scored_category), 4),
            "failed_count": sum(1 for score in category_scores if score.error),
            "expected_blocked_count": sum(1 for score in category_scores if score.expected_blocked),
        }

    scored = [score for score in scores if not score.expected_blocked]
    report = {
        "version": 1,
        "pipeline": pipeline,
        "pathway": pathway,
        "repeat_count": repeat_count,
        "compute_mode": compute_mode,
        "benchmark_host": benchmark_host(compute_mode),
        "corpus": str(corpus_dir),
        "category_filter": category_filter or None,
        "bucket_filter": bucket_filter or None,
        "document_count": len(scores),
        "scored_document_count": len(scored),
        "overall_percent": round(sum(score.overall for score in scored) / len(scored) * 100, 1) if scored else 0.0,
        "avg_elapsed_seconds": round(sum(score.elapsed_seconds for score in scored) / len(scored), 4) if scored else 0.0,
        "total_elapsed_seconds": round(sum(score.elapsed_seconds for score in scored), 4),
        "failed_count": sum(1 for score in scores if score.error),
        "expected_blocked_count": sum(1 for score in scores if score.expected_blocked),
        "categories": categories,
        "documents": [
            {
                "id": score.doc_id,
                "file": score.file,
                "category": score.category.split("/")[0],
                "bucket": score.bucket,
                "status": "expected_blocked" if score.expected_blocked else ("failed" if score.error else "scored"),
                "overall_percent": round(score.overall * 100, 1),
                "heading_recall_percent": round(score.heading_recall * 100, 1),
                "table_accuracy_percent": round(score.table_accuracy * 100, 1),
                "content_completeness_percent": round(score.content_completeness * 100, 1),
                "markdown_valid": score.markdown_valid,
                "artifacts_found": score.artifacts_found,
                "elapsed_seconds": round(score.elapsed_seconds, 3),
                "elapsed_runs_seconds": [round(value, 3) for value in score.elapsed_runs_seconds],
                "error": score.error,
                "blocked_reason": score.blocked_reason,
            }
            for score in scores
        ],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Upmarket benchmark scorer")
    parser.add_argument("--corpus")
    parser.add_argument("--convert-one", type=Path, help=argparse.SUPPRESS)
    parser.add_argument("--pipeline", default="")
    parser.add_argument("--pathway", default="")
    parser.add_argument("--category", default="")
    parser.add_argument("--bucket", choices=("native", "digital-complex", "scanned-or-unknown", "blocked"), default="")
    parser.add_argument("--fail-below", type=int, default=0)
    parser.add_argument("--repeat", type=int, default=1, help="number of conversion runs per document for average wall-time")
    parser.add_argument("--compute-mode", choices=("auto", "cpu", "gpu", "ane"), default="auto", help="requested compute mode for pathways that support CPU/GPU/Apple Neural Engine selection")
    parser.add_argument("--json-output", type=Path)
    args = parser.parse_args()

    if args.convert_one:
        try:
            markdown, elapsed = convert_document(args.convert_one, args.pipeline or "fast", args.pathway or None)
            print(json.dumps({"success": True, "markdown": markdown, "elapsed_seconds": elapsed}))
            sys.exit(0)
        except Exception as exc:
            print(json.dumps({"success": False, "error": str(exc)}))
            sys.exit(1)

    if not args.corpus:
        parser.error("--corpus is required unless --convert-one is used")

    sys.exit(run_benchmark(
        corpus_dir=Path(args.corpus),
        pipeline=args.pipeline,
        pathway=args.pathway,
        category_filter=args.category,
        bucket_filter=args.bucket,
        fail_below=args.fail_below,
        repeat_count=args.repeat,
        compute_mode=args.compute_mode,
        json_output=args.json_output,
    ))
