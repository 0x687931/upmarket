# Native PDFKit Inspection

This note defines the native Apple lane for improving PDF-to-Markdown quality without shipping GPL or incompatible PDF engines. It is clean-room work: reference tools may provide benchmark output, but source code from Poppler or other restricted projects is not used.

## Current Result

`swift-pdfkit` scores 83.2% across the 60-document PDF corpus at 0.009s per document on the current M4 Pro benchmark host. The first targeted improvement was a figure-text mode that preserves short axis/label extracts as fenced text instead of treating them as headings.

## Native Toolkit

- `PDFKit`: opens PDFs, handles password state, extracts native digital text, and renders pages for fallback analysis.
- `Vision`: performs OCR, document structure analysis, image quality checks, rectangle/text detection, and image classification. Vision chooses CPU, GPU, or Apple Neural Engine internally where supported by the OS.
- `Core ML`: can host a small document classifier, routing model, or quality estimator. Core ML can use CPU, GPU, and Neural Engine; actual placement must be measured with Instruments.
- `CoreGraphics` / `ImageIO`: render page thumbnails, inspect raster properties, and detect scanned or image-heavy PDFs without external dependencies.
- `Metal Performance Shaders`: reserved for future custom image preprocessing only if Vision/Core ML do not cover the need.

## Failure Classes

- Multi-column academic PDFs: `PDFPage.string` loses reading order and table boundaries.
- Dense tables and handbooks: plain text extraction drops row/column semantics.
- RTL PDFs: extracted text needs direction-aware ordering and validation.
- Figure-only PDFs: native text is often present, but Markdown needs a figure/text layout mode.
- Password-protected samples: expected failure unless the user supplies a password.

## Improvement Plan

1. Keep `PDFPage.string` as the fast baseline for simple digital PDFs.
2. Add a native page classifier using PDFKit metadata, rendered page thumbnails, Vision observations, and text-density signals.
3. For failing digital PDFs, extract word/line geometry from native selection bounds or CoreGraphics-backed page analysis instead of relying only on full-page strings.
4. Add table and multi-column reconstruction only where the classifier predicts it is needed.
5. Use Vision OCR for scanned or image-heavy pages, with user-facing copy that says only "advanced extraction" or "image text extraction".
6. Benchmark each mode separately and record accuracy, wall time, and measured CPU/GPU/Neural Engine use before changing release defaults.

## Classifier Contract

`NativeDocumentClassifier` is the routing evidence service for PDFs. It samples representative pages and returns:

- `pdfkit` for simple digital text and short figure text.
- `vision_ocr` for image-heavy/scanned PDFs when Vision text recognition is available.
- `enhanced` for dense tables, RTL text, or likely multi-column layout.

The classifier must remain fail-soft. If Vision or Core ML are unavailable, the evidence records that capability state and the recommendation must not require that framework. If an enhanced or Vision route fails during conversion, the app falls back to the native PDFKit path where possible.

Runtime logs and support reports must use the neutral component codes in `docs/release/DIAGNOSTIC_COMPONENTS.md`; they must not expose toolkit or package names.

## User-Facing Rule

Do not expose internal toolkit names such as PDFKit, Vision, Core ML, Python, Docling, Poppler, or OCR engines in normal UI copy. Technical names belong in licenses, diagnostics, developer docs, and benchmark artifacts only.
