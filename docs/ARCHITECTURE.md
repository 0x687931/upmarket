# Upmarket Architecture

Two flowcharts: the conversion pipeline a user triggers, and the model download
flow that unlocks the AI tier.

## Conversion Pipeline

```
User drops / opens a file
         │
         ▼
  ConversionQueue.add()
  ┌─ job created, stage = queued
  │  liveness monitor starts (checks every 5s, marks stalled after 60s)
         │
         ▼
  ConversionRunner.run()
  ├─ stage: copying     → copies file to sandboxed per-job temp workspace
  ├─ stage: analysing   → NativeDocumentClassifier inspects PDF structure
  │                       (skipped for non-PDF formats)
  ├─ stage: extracting  → route by file type:
  │
  │   PDF ─────────────────────────────────────────────────────────────┐
  │   │  classifier → "digital text"  → PDFKit (fast, in-process)      │
  │   │  classifier → "scanned/complex" → Vision OCR + table banding   │
  │   │  useAI = true & Granite-eligible → native Granite-Docling      │
  │   │                                    (mlx-swift), else Vision     │
  │   │  quality-selected: PDFKit baseline vs Vision OCR                │
  │   └────────────────────────────────────────────────────────────────┘
  │
  │   Audio (mp3, m4a, wav…)
  │   └─ Speech framework (in-process)
  │      └─ fallback: AVFoundation metadata (in-process)
  │
  │   Image (jpg, png, tiff…) → ImageIO/CoreGraphics metadata (in-process)
  │
  │   DOCX / PPTX / XLSX     → SwiftOfficeMarkdown (in-process)
  │   HTML                   → NativeHTMLConverter / libxml2 (in-process)
  │   TXT / MD / CSV         → NativeTextConverter (in-process)
  │   EPUB                   → NativeEPUBConverter (ZipReader + HTML)
  │
  ├─ stage: postProcessing → NaturalLanguage cleanup and metadata extraction
  └─ stage: complete / failed / cancelled
         │
         ▼
  Result shown in shelf
  Copy / Save / Open in editor / Retry
```

### Process boundary

Every engine runs **in-process** inside `Upmarket.app` — there is no Python
runtime and no helper process. Apple frameworks (PDFKit, Vision, Speech,
AVFoundation, ImageIO), the vendored SwiftOfficeMarkdown/HTML/text/EPUB
converters, and the native Granite-Docling VLM (`UpmarketVLM`, mlx-swift) all
execute within the app and its sandbox.

### Conversion engines by tier

| Upmarket tier | Engine                                   | Notes                         |
|---------------|------------------------------------------|-------------------------------|
| Basic         | PDFKit / Vision / Office / HTML / text    | native, no download           |
| Pro           | same native engines (complex PDF, sheets) | tier gate, no download        |
| AI (Max)      | Granite-Docling-258M via mlx-swift        | `granite_docling` model download  |

Output is Markdown (`DocTags → Markdown` for the Granite path).

---

## Model Download Flow

```
App launch
    │
    ▼
ModelManager.checkModels()
    │
    ├─ installState = checking
    │       │
    │       ├─ models dir exists + manifest valid + checksums match?
    │       │       YES → installState = ready
    │       │       NO  → installState = failed  (surfaced in Settings)
    │
    ▼
User opens Settings → Models
    │
    ├─ Shows: Apple Silicon requirement, disk space needed, install state
    │
    └─ Taps "Download"
            │
            ▼
    ModelManager.downloadRequiredModels()
            │
            ├─ Fetch manifest from first-party Apple-hosted URL
            │   (HF_HUB_OFFLINE=1 — Hugging Face Hub not contacted at runtime)
            │
            ├─ Download weights + metadata to staging directory
            │   Required files: weights, model index, chat_template.jinja,
            │                   tokenizer metadata
            │
            ├─ Verify checksums and expected file list
            │
            ├─ Atomically promote staging → models/
            │   (partial or corrupt downloads are never promoted)
            │
            └─ installState = ready
                    │
                    ▼
            AI tier unlocked
            ConversionRunner routes Granite-eligible useAI=true jobs to
            UpmarketVLM.GraniteDoclingEngine (mlx-swift, in-process)
```

### Model storage

Models are stored in `~/Library/Application Support/Upmarket/models/`.
The developer intake path (Hugging Face snapshot) is available behind
`UPMARKET_ENABLE_DEVELOPER_MODEL_INTAKE=1` for local development only.
