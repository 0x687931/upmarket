#!/bin/bash
# seed_corpus.sh
# Downloads freely licensed documents to seed the test corpus.
# All documents are CC BY, public domain, or explicitly free for testing.
#
# Usage: ./scripts/seed_corpus.sh

set -euo pipefail

CORPUS="tests/corpus"

echo "==> Seeding Upmarket test corpus..."
echo ""

# ── PDF Digital / Academic ─────────────────────────────────────────────────

echo "--- PDF Digital / Academic ---"

# Docling technical report (CC BY) — ironic choice
curl -sL "https://arxiv.org/pdf/2408.09869" \
    -o "$CORPUS/pdf_digital/academic/docling_technical_report.pdf" \
    && echo "  ✓ docling_technical_report.pdf"

# Attention Is All You Need (CC BY)
curl -sL "https://arxiv.org/pdf/1706.03762" \
    -o "$CORPUS/pdf_digital/academic/attention_is_all_you_need.pdf" \
    && echo "  ✓ attention_is_all_you_need.pdf"

# BERT paper (CC BY)
curl -sL "https://arxiv.org/pdf/1810.04805" \
    -o "$CORPUS/pdf_digital/academic/bert_paper.pdf" \
    && echo "  ✓ bert_paper.pdf"

# ── PDF Digital / Technical ────────────────────────────────────────────────

echo ""
echo "--- PDF Digital / Technical ---"

# Swift programming language (Apple, public)
curl -sL "https://docs.swift.org/swift-book/documentation/the-swift-programming-language/" \
    -o "$CORPUS/web/html/swift_book.html" 2>/dev/null \
    && echo "  ✓ swift_book.html" || echo "  - swift_book.html (skipped)"

# ── Web / HTML ─────────────────────────────────────────────────────────────

echo ""
echo "--- Web / HTML ---"

# Wikipedia article (CC BY-SA)
curl -sL "https://en.wikipedia.org/wiki/Markdown" \
    -o "$CORPUS/web/html/wikipedia_markdown.html" \
    && echo "  ✓ wikipedia_markdown.html"

# ── Data Formats ───────────────────────────────────────────────────────────

echo ""
echo "--- Data Formats ---"

# Sample CSV
cat > "$CORPUS/data/csv/sample_data.csv" << 'CSV'
Name,Age,City,Occupation
Alice Johnson,32,New York,Engineer
Bob Smith,45,London,Doctor
Carol White,28,Sydney,Designer
David Brown,51,Toronto,Manager
CSV
echo "  ✓ sample_data.csv"

# Sample JSON
cat > "$CORPUS/data/json/sample_data.json" << 'JSON'
{
  "company": "Upmarket Inc",
  "founded": 2026,
  "products": [
    {
      "name": "Upmarket",
      "price": 4.99,
      "tier": "basic",
      "description": "Convert everyday documents to Markdown"
    },
    {
      "name": "Upmarket + AI",
      "price": 9.99,
      "tier": "pro",
      "description": "Advanced AI for complex documents"
    }
  ],
  "supported_formats": ["PDF", "DOCX", "PPTX", "XLSX", "HTML", "EPUB"]
}
JSON
echo "  ✓ sample_data.json"

# Copy our existing test PDF
cp ~/Downloads/23wa.pdf "$CORPUS/pdf_digital/academic/algebra_rings_fields.pdf" 2>/dev/null \
    && echo "  ✓ algebra_rings_fields.pdf (from Downloads)" \
    || echo "  - algebra_rings_fields.pdf (not found in Downloads)"

echo ""
echo "==> Corpus seeded. Run ./scripts/benchmark.sh to validate."
echo ""
echo "Next: Add .expected.md ground truth files for each document."
echo "See docs/CORPUS_STRATEGY.md for instructions."
