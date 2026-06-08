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
  │   │  classifier → "scanned"       → Vision OCR (in-process)        │
  │   │  classifier → "complex"       → Python/Docling (helper)        │
  │   │  useAI = true                 → quality-selected:              │
  │   │                                  PDFKit baseline, then best of  │
  │   │                                  Vision OCR / Docling / Granite │
  │   └────────────────────────────────────────────────────────────────┘
  │
  │   Audio (mp3, m4a, wav…)
  │   └─ Speech framework (in-process)
  │      └─ fallback: Python/MarkItDown (helper)
  │         └─ fallback: AVFoundation metadata (in-process)
  │
  │   Image (jpg, png, tiff…) → ImageIO/CoreGraphics metadata (in-process)
  │
  │   Video (mp4, mov…)       → AVFoundation metadata (in-process)
  │
  │   DOCX / PPTX / XLSX /
  │   HTML / CSV / XML / …   → Python/Docling via helper process
  │
  ├─ stage: postProcessing → NaturalLanguage cleanup and metadata extraction
  └─ stage: complete / failed / cancelled
         │
         ▼
  Result shown in shelf
  Copy / Save / Open in editor / Retry
```

### Process boundary

Apple-native paths (PDFKit, Vision, Speech, AVFoundation, ImageIO) run
**in-process** inside `Upmarket.app`. Python paths (Docling, MarkItDown,
pdfium) run inside `UpmarketRuntimeHelper` — a separate sandboxed process
launched per job. A helper crash or hang maps to a typed Swift error and
cannot take down the main app.

### Docling pipelines used

| Upmarket tier | Docling pipeline      | Model              |
|---------------|-----------------------|--------------------|
| Enhanced      | StandardPdfPipeline   | layout + table OCR |
| AI            | VlmPipeline           | Granite Docling MLX|

Output is always `export_to_markdown()` for v1.0. HTML output
(`export_to_html()`) is a v1.1 candidate for Enhanced and AI paths.

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
            ConversionRunner routes useAI=true jobs to
            UpmarketRuntimeHelper → VlmPipeline (Granite MLX)
```

### Model storage

Models are stored in `~/Library/Application Support/Upmarket/models/`.
The developer intake path (Hugging Face snapshot) is available behind
`UPMARKET_ENABLE_DEVELOPER_MODEL_INTAKE=1` for local development only.
