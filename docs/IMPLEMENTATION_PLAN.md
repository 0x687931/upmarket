# Upmarket — Implementation Plan

## Overview

Upmarket converts documents to Markdown using on-device AI. The app runs 100% offline on Apple Silicon via Metal, with no cloud dependency after initial model download.

## Version 1 Goals

- Drag-and-drop / file picker to select a document
- Convert to Markdown in the background
- Show live progress during conversion
- Copy or save the Markdown output
- Download ML models on first use (only when needed)
- Run fully offline after models are cached

---

## Technical Stack

| Layer | Technology | Rationale |
|---|---|---|
| UI | SwiftUI | Native macOS, App Store required |
| Python runtime | BeeWare Python-Apple-support | App Store compatible embedded CPython |
| Python bridge | PythonKit | Swift ↔ Python interop |
| Document conversion | Docling | Best-in-class open source (MIT) |
| Layout/table ML | PyTorch + MPS | Auto-accelerated on Apple Silicon |
| VLM (optional) | MLX (SmolDocling) | Native Apple Silicon inference |
| Model delivery | In-app download v1 → Background Assets v2 | Progressive enhancement |

---

## Phase 1: Project Scaffold (Week 1)

### 1.1 Xcode Project Setup
- Create Xcode project: `Upmarket`, bundle ID `com.upmarket.app`
- Target: macOS Ventura 13.3+ (for Background Assets compatibility)
- Enable App Sandbox
- Add entitlements: `com.apple.security.network.client` (for model download)

### 1.2 Python Runtime Integration
- Download BeeWare `Python-Apple-support` (Python 3.12)
- Add `Python.xcframework` to Xcode project
- Add Swift Package Manager dependency: `PythonKit`
- Verify Python interpreter launches from Swift

### 1.3 Python Environment
- Create `requirements.txt` with pinned dependencies
- Script to build self-contained Python stdlib + site-packages into app bundle
- Key packages: `docling`, `mlx-vlm`, `torch` (MPS), pinned for compatibility

---

## Phase 2: Python Bridge (Week 2)

### 2.1 Docling Bridge Module (`UpmarketPython/docling_bridge/`)

```python
# converter.py
def convert(file_path: str, options: dict) -> dict:
    """
    Convert a document file to Markdown.
    Returns: {success, markdown, metadata, error}
    """
```

### 2.2 Model Manager (`UpmarketPython/models/`)

```python
# model_manager.py
def check_models_available() -> dict:
    """Returns which models are downloaded."""

def download_model(name: str, progress_callback) -> bool:
    """Downloads a specific model with progress reporting."""
```

### 2.3 Swift Service Layer (`Upmarket/Services/`)

- `PythonBridge.swift` — initialises PythonKit, sets `HF_HUB_OFFLINE`
- `ConversionService.swift` — calls Python bridge, publishes progress
- `ModelManager.swift` — checks/triggers model downloads, persists state

---

## Phase 3: Core UI (Week 3)

### 3.1 Views

```
ContentView
├── DropZoneView          # Drag-and-drop target + file picker button
├── ConversionProgressView # Progress bar + status messages
├── OutputView            # Markdown preview + copy/save actions
└── ModelDownloadView     # First-launch model download sheet
```

### 3.2 App Flow

```
Launch
  ↓
Check models (ModelManager)
  ├─ Missing → show ModelDownloadView (non-blocking for basic conversion)
  └─ Present → ready
  ↓
DropZoneView (idle state)
  ↓
User drops file
  ↓
ConversionService.convert(file)
  ↓
ConversionProgressView (live updates via @Published)
  ↓
OutputView (Markdown result)
  ↓
Copy / Save As / Convert Another
```

### 3.3 Model Download Strategy

- On first launch: detect no models, show optional download prompt
- Run basic conversion immediately with layout-only pipeline (no VLM)
- Prompt to download SmolDocling only if document needs VLM (complex layout, figures)
- Store models in `~/Library/Application Support/Upmarket/models/`
- Set `HF_HUB_OFFLINE=1` after download; never call HuggingFace Hub again

---

## Phase 4: Polish + App Store (Week 4)

### 4.1 App Store Requirements
- App Sandbox enabled
- Privacy manifest (`PrivacyInfo.xcprivacy`)
- No private API usage
- Network entitlement justification: model download only, first launch
- App Review notes explaining model download

### 4.2 Model Size Management
- Base app bundle target: < 50MB
- Models downloaded to Application Support (not counted in app bundle)
- Show model sizes before download with user confirmation

### 4.3 Performance
- Conversion runs on background thread (never block UI)
- Progress reported via `AsyncStream` from Python bridge
- Cancel button during conversion

### 4.4 Error Handling
- Unsupported file type: clear user message
- Conversion failure: show error with option to retry
- Model download failure: retry with exponential backoff
- Offline with no models: clear explanation

---

## Phase 5: Background Assets (v2, post-launch)

After v1 ships and validates the market:

- Register as Background Assets extension
- Host models on Apple CDN or own S3
- Models download before first app launch
- Delta updates when models are refreshed
- Targets macOS 26+ Managed Background Assets for zero-config updates

---

## Dependency Versions (to pin)

```
docling==2.x.x
docling-core==2.x.x
docling-parse==5.x.x
torch==2.x.x  (MPS support)
mlx==0.x.x
mlx-vlm==0.x.x  # pin carefully — conflicts with docling-ibm-models
transformers==4.x.x  # must satisfy both mlx-vlm and docling-ibm-models
huggingface_hub==0.x.x
```

> Known conflict: `mlx-vlm >= 4.51.3` requires a different `transformers` version than `docling-ibm-models < 4.43.0`. Resolve by testing and pinning before bundling.

---

## Open Questions / Risks

| Risk | Mitigation |
|---|---|
| PythonKit + App Sandbox compatibility | Test early in Phase 1; BeeWare has documented this working |
| mlx-vlm / docling-ibm-models version conflict | Resolve in Phase 2 before bundling |
| App bundle size with Python stdlib | Strip unused stdlib modules in build script |
| App Review rejection for model download | Include clear Privacy Manifest + Review notes |
| Intel Mac support | PyTorch CPU fallback; mark Apple Silicon as recommended |

---

## Success Criteria for v1

- [ ] Converts a PDF to Markdown correctly
- [ ] Converts a DOCX to Markdown correctly
- [ ] Runs fully offline after first model download
- [ ] App bundle < 100MB (models excluded)
- [ ] Passes App Store review
- [ ] Conversion of a 10-page PDF completes in < 30 seconds on M1
