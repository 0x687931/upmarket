"""
Upmarket PDF post-processor.
Converts pdfium extraction to clean structured Markdown.

Uses actual font sizes from PDF metadata (not guessed from rect heights)
to reliably detect headings vs body text.

Key constraint: get_font_size() must only be called on PdfTextObj (type=1).
Calling it on PdfObject (type=2, path) or PdfImage (type=3) hangs in the
xcframework build of pypdfium2 due to undefined behaviour in the C binding.
"""

import re
import sys
from collections import Counter
from dataclasses import dataclass
from docling_bridge.security import sanitise_text_block, SafeRegex

# pdfium object type constants
PDF_OBJ_TYPE_TEXT  = 1
PDF_OBJ_TYPE_PATH  = 2
PDF_OBJ_TYPE_IMAGE = 3


@dataclass
class Block:
    text: str
    font_size: float
    x: float
    y: float      # top-down (converted from PDF coords)
    width: float
    page: int


def pdf_to_clean_markdown(file_path: str, password: str | None = None) -> tuple[str, int]:
    """
    Convert a PDF to clean structured Markdown.
    Returns (markdown, page_count).
    """
    import pypdfium2 as pdfium

    doc = pdfium.PdfDocument(file_path, password=password)
    page_count = len(doc)
    all_blocks: list[Block] = []

    for page_idx in range(page_count):
        page = doc[page_idx]
        page_height = page.get_height()

        # Build font_size map: y_bottom → font_size
        # IMPORTANT: only call get_font_size() on TEXT objects (type=1).
        # Calling it on path/image objects hangs in the xcframework pdfium build.
        font_map: dict[float, float] = {}
        for obj in page.get_objects():
            try:
                if obj.type != PDF_OBJ_TYPE_TEXT:
                    continue
                size = obj.get_font_size()
                bounds = obj.get_bounds()   # (x0, y0, x1, y1)
                if size > 0:
                    y_key = round(bounds[1], 1)
                    font_map[y_key] = max(font_map.get(y_key, 0), size)
            except Exception:
                pass

        # Get text blocks and match to font sizes
        tp = page.get_textpage()
        for i in range(tp.count_rects()):
            rect = tp.get_rect(i)
            text = sanitise_text_block(tp.get_text_bounded(*rect).strip())
            if not text:
                continue

            # Look up font size by y-coordinate proximity
            y_bottom = round(rect[1], 1)
            font_size = font_map.get(y_bottom, 0)
            if font_size == 0:
                for dy in [0.5, 1.0, 2.0, 3.0, 5.0]:
                    font_size = font_map.get(round(y_bottom + dy, 1), 0)
                    if font_size: break
                    font_size = font_map.get(round(y_bottom - dy, 1), 0)
                    if font_size: break

            all_blocks.append(Block(
                text=text,
                font_size=font_size,
                x=rect[0],
                y=page_height - rect[3],
                width=rect[2] - rect[0],
                page=page_idx,
            ))

        tp.close()
        page.close()

    doc.close()

    if not all_blocks:
        return "", page_count

    return _blocks_to_markdown(all_blocks, page_count), page_count


def _blocks_to_markdown(blocks: list[Block], page_count: int) -> str:
    sizes = [b.font_size for b in blocks if b.font_size > 0]
    if not sizes:
        return "\n\n".join(_clean_text(b.text) for b in blocks)

    # Body = most frequent font size
    size_counts = Counter(round(s, 0) for s in sizes)
    body_size = size_counts.most_common(1)[0][0]

    # Map larger sizes to H1/H2/H3
    larger_sizes = sorted(
        {round(s, 0) for s in sizes if round(s, 0) > body_size + 1},
        reverse=True
    )
    size_to_level = {s: i + 1 for i, s in enumerate(larger_sizes[:3])}

    parts: list[str] = []
    pending: list[str] = []
    prev_page = -1

    def flush():
        if pending:
            para = _clean_paragraph(" ".join(pending))
            if para:
                parts.append(para)
            pending.clear()

    for block in blocks:
        if block.page > prev_page and prev_page >= 0:
            flush()
            if page_count > 1:
                parts.append("\n---\n")
        prev_page = block.page

        text = _clean_text(block.text)
        if not text or _is_noise(text, block):
            continue

        level = size_to_level.get(round(block.font_size, 0), 0)

        if level == 1:
            flush(); parts.append(f"# {text}")
        elif level == 2:
            flush(); parts.append(f"## {text}")
        elif level == 3:
            flush(); parts.append(f"### {text}")
        else:
            cleaned = _strip_toc_leaders(text)
            if cleaned:
                pending.append(cleaned)
            if text[-1] in '.!?:':
                flush()

    flush()

    result = "\n\n".join(p for p in parts if p.strip())
    return _final_cleanup(result)


# MARK: - Text cleaning

LIGATURES = {
    'ﬁ': 'fi', 'ﬂ': 'fl', 'ﬃ': 'ffi', 'ﬄ': 'ffl',
    'ﬀ': 'ff', 'ﬅ': 'st', 'ﬆ': 'st',
    '\xad': '',    # soft hyphen
    '�': '',  # replacement character
}


def _clean_text(text: str) -> str:
    for bad, good in LIGATURES.items():
        text = text.replace(bad, good)
    text = re.sub(r'(\w)-\n(\w)', r'\1\2', text)
    text = re.sub(r'[ \t]+', ' ', text)
    return text.strip()


def _clean_paragraph(text: str) -> str:
    text = re.sub(r' +', ' ', text)
    text = re.sub(r'\.([A-Z])', r'. \1', text)
    return text.strip()


def _strip_toc_leaders(text: str) -> str:
    # Match TOC dot leaders: ". . . . 42" or "......... 42" or "   42"
    # Use atomic patterns to avoid catastrophic backtracking (ReDoS).
    # Pattern: one or more (dot + optional space) groups, then optional page number.
    # We use [. ]+ (character class, no nesting) instead of (\s*\.\s*){3,}.
    text = re.sub(r'[. ]{5,}\d*\s*$', '', text)
    text = re.sub(r'\s{3,}\d+\s*$', '', text)
    return text.strip()


def _is_noise(text: str, block: Block) -> bool:
    stripped = text.strip()
    if re.match(r'^\d{1,4}$', stripped):
        return True
    if re.match(r'^[Pp]age\s+\d+', stripped):
        return True
    if re.match(r'^\d+\s+of\s+\d+$', stripped, re.IGNORECASE):
        return True
    if re.search(r'\bpage\s+\d+\s*$', stripped, re.IGNORECASE):
        return True
    return False


def _final_cleanup(text: str) -> str:
    text = re.sub(r'\n{3,}', '\n\n', text)
    text = re.sub(r'^---\n\n', '', text)
    text = re.sub(r'\n\n---$', '', text)
    return text.strip()
