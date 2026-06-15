# Plan: remove all Python from conversion (Swift-native by tier)

**Status:** investigation / not started. **Goal:** replace every Python conversion dependency
with a Swift-native implementation, **within the existing tier boundaries**.

> **Constraint — tiers are fixed.** The Basic/Pro/Max split exists for **revenue**, not
> technical reasons. This plan does **not** move features between tiers, change gating, or
> touch distribution/monetization. Each tier must deliver the **same** capabilities it does
> today, just with Python swapped for native code.

## Where Python lives today (by tier)

| Layer | Python today | Native status |
|---|---|---|
| **Basic** — PDF text, images, docx, txt/md/csv, html | *(none)* | ✅ Done — PDFKit, Vision, ImageIO, SwiftOfficeMarkdown, NativeText/HTML |
| **Pro Office** — xlsx/pptx/xls/ppt | `python-pptx`, `openpyxl`, `xlrd`, `pandas` | ✅ Native engine exists (SwiftOfficeMarkdown); routing still points at Python |
| **Pro OCR** — scanned PDFs | `ocrmac` | ✅ Trivial — `ocrmac` *is* Apple Vision; swap to `VNRecognizeTextRequest` |
| **Pro PDF parse** — text + geometry | `docling-parse` | 🟡 Mostly there — PDFKit + `CGPDFScanner`; docling-parse adds finer cell geometry |
| **Pro layout + tables** | `docling-ibm-models` (layout model + TableFormer) | 🔴 Real gap — ML models, no Apple-native equivalent |
| **Max VLM** — image/scanned → markdown | `mlx-vlm` (Granite Docling) + `torch`/`transformers` fallback | 🔴 Real gap — vision-language model |

Tiered Python deps: `requirements-pro.txt` (Docling + Office parsers + ocrmac), `requirements-ai.txt`
(torch, transformers, mlx, mlx-vlm). Entry point: `UpmarketPython/docling_bridge/converter.py`.

## Pro tier — replace the Enhanced engine in place

`converter.py` Enhanced = Docling `StandardPdfPipeline`:

1. **PDF parsing** → PDFKit / CoreGraphics `CGPDFScanner` (native, ~90% there; docling-parse adds finer geometry).
2. **OCR** → already Apple Vision via `ocrmac` (`converter.py:294` `OcrMacOptions`). Swap to native `VNRecognizeTextRequest`. No model needed.
3. **Office (xlsx/pptx/xls/ppt)** → SwiftOfficeMarkdown (native engine already in the app).
4. **Layout analysis** → `docling-ibm-models` RT-DETR-style detector (regions + reading order).
5. **Table structure** → **TableFormer** (table image → row/col/cell structure).

Native approach for (4)+(5): convert both models to **Core ML** (`coremltools`, PyTorch→CoreML),
run on the Neural Engine, and reimplement Docling's assembly (reading order, cell→Markdown) in Swift.

- **Feasibility:** good in principle — models are open and standard architectures.
- **Effort:** high — two non-trivial conversions (detector post-processing/NMS; TableFormer sequence decode) + a Swift inference + assembly layer.
- **Risk:** output parity (table accuracy), CoreML conversion friction (unsupported ops, dynamic shapes).

After (2)+(3), Pro's only remaining Python dependency is the layout/table models — a single focused Core ML project.

## Max tier — port the VLM to MLX-Swift

`converter.py:459` runs Granite Docling via `mlx-vlm` `stream_generate`: render page → image
(`pypdfium2`), stream **DocTags** tokens, assemble via `docling-core` → Markdown. Fallback:
Docling `VlmPipeline` (torch/transformers).

Native approach — it already runs on **MLX (Apple's framework)**, which has Swift bindings:
- **Inference:** `mlx-swift` (+ `mlx-swift-examples` VLM runners); weights are already MLX format.
- **Tokenizer / chat template:** `swift-transformers`.
- **PDF → image:** PDFKit (replaces `pypdfium2`).
- **DocTags → Markdown:** Swift reimplementation of the `DocTagsDocument`/`DoclingDocument` grammar.

- **Feasibility:** strong — already MLX; Apple maintains the Swift bindings; `torch`/`transformers` are only a droppable fallback.
- **Effort:** high but contained — model load + generation loop + tokenizer + DocTags parser.
- **Risk:** porting Granite Docling specifically into `mlx-swift-examples` (model class/config), streaming-progress parity, memory budget for Granite Vision.

**Foundation Models (macOS 26):** Apple's on-device LLM is now available, but it's a *text* model,
not a document-layout VLM — useful for the Writing-Tools refinement step, **not** a Docling/VLM
replacement. Do not conflate.

## Cross-cutting prerequisite: the assembly layer

Both tiers rely on **`docling-core`** to turn model output into a structured `DoclingDocument`
(reading order, hierarchy, tables, Markdown export). A Swift port of this assembly/serialization is
a **shared prerequisite** for both Pro and Max — replacing models without it gets you nowhere.

## Phasing (technical only; no tier changes)

1. **Quick wins (low risk):** within Pro, route Office → SwiftOfficeMarkdown and OCR → native Vision. Removes Python from a large share of Pro conversions; leaves only layout/tables.
2. **Pro Core ML project:** layout + TableFormer → Core ML + Swift assembly; validate table accuracy vs corpus.
3. **Max MLX-Swift project:** port Granite Docling to `mlx-swift` + `swift-transformers` + Swift DocTags parser.
4. **Retire Python:** once both land, drop `requirements-*.txt`, the runtime, and the Swift↔Python boundary.

## Technical note (not a tier/distribution proposal)

Going fully native removes the downloadable Python runtime entirely. That is a purely technical
consequence; any distribution/delivery decision is out of scope for this plan.

## Candidate Swift dependencies

- `coremltools` (build-time, model conversion), Core ML + Vision (runtime).
- `mlx-swift`, `mlx-swift-examples` (VLM inference).
- `swift-transformers` (tokenizers / chat templates).
- PDFKit + CoreGraphics (PDF parse + page rasterization).
