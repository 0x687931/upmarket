"""
Upmarket PDF post-processor.
Converts pdfium extraction to clean structured Markdown.

Uses actual font sizes from PDF metadata (not guessed from rect heights)
to reliably detect headings vs body text — no magic threshold tuning needed.
"""

import re
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass


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

        # Map y_bottom → font_size from actual PDF text objects
        font_map: dict[float, float] = {}
        for obj in page.get_objects():
            try:
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
            text = tp.get_text_bounded(*rect).strip()
            if not text:
                continue

            # Look up font size — try exact match then nearby y values
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
                y=page_height - rect[3],   # convert to top-down
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
    # Determine font size roles from the document's own data
    sizes = [b.font_size for b in blocks if b.font_size > 0]
    if not sizes:
        return "\n\n".join(_clean_text(b.text) for b in blocks)

    # Body = most frequent size (the dominant reading font)
    size_counts = Counter(round(s, 0) for s in sizes)
    body_size = size_counts.most_common(1)[0][0]

    # Collect all distinct sizes larger than body for heading levels
    larger_sizes = sorted(
        {round(s, 0) for s in sizes if round(s, 0) > body_size + 1},
        reverse=True
    )
    # Map to H1/H2/H3: largest → H1, next → H2, next → H3
    size_to_level = {}
    for i, s in enumerate(larger_sizes[:3]):
        size_to_level[s] = i + 1

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
        if not text:
            continue

        if _is_noise(text, block):
            continue

        rounded_size = round(block.font_size, 0)
        level = size_to_level.get(rounded_size, 0)

        if level == 1:
            flush()
            parts.append(f"# {text}")
        elif level == 2:
            flush()
            parts.append(f"## {text}")
        elif level == 3:
            flush()
            parts.append(f"### {text}")
        else:
            # Body — clean TOC dot leaders and accumulate
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
    '­': '',   # soft hyphen
    '�': '',   # replacement character
}

def _clean_text(text: str) -> str:
    for bad, good in LIGATURES.items():
        text = text.replace(bad, good)
    # Rejoin hyphenated line breaks
    text = re.sub(r'(\w)-\n(\w)', r'\1\2', text)
    text = re.sub(r'[ \t]+', ' ', text)
    return text.strip()


def _clean_paragraph(text: str) -> str:
    text = re.sub(r' +', ' ', text)
    text = re.sub(r'\.([A-Z])', r'. \1', text)
    return text.strip()


def _strip_toc_leaders(text: str) -> str:
    """Remove dot leaders: 'Section title . . . . . 42' → 'Section title'"""
    # Repeated dots pattern: ". . . . . 42"
    text = re.sub(r'(\s*\.\s*){3,}\s*\d*\s*$', '', text)
    # Continuous dots: ".......... 42"
    text = re.sub(r'\.{3,}\s*\d*\s*$', '', text)
    # Trailing page number after whitespace
    text = re.sub(r'\s{3,}\d+\s*$', '', text)
    return text.strip()


def _is_noise(text: str, block: Block) -> bool:
    """Filter page numbers and running headers."""
    stripped = text.strip()
    # Pure page number
    if re.match(r'^\d{1,4}$', stripped):
        return True
    # "Page N" or "N of M"
    if re.match(r'^[Pp]age\s+\d+', stripped):
        return True
    if re.match(r'^\d+\s+of\s+\d+$', stripped, re.IGNORECASE):
        return True
    # Running header pattern: contains "page N" at end
    if re.search(r'\bpage\s+\d+\s*$', stripped, re.IGNORECASE):
        return True
    return False


def _final_cleanup(text: str) -> str:
    text = re.sub(r'\n{3,}', '\n\n', text)
    text = re.sub(r'^---\n\n', '', text)
    text = re.sub(r'\n\n---$', '', text)
    return text.strip()
