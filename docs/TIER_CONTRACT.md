# Upmarket Tier Contract

**This document is the single source of truth for what each tier provides.**
All architectural decisions, build scripts, UI copy, and tests derive from this contract.
Update this first; everything else follows.

---

## Overview

| Tier | Price | Download | Capabilities |
|------|-------|----------|--------------|
| **Basic** | Free | ~50MB libraries (bundled) | Native Apple conversion |
| **Pro** | $9.99 | ~350MB runtime | Native + Enhanced (layout + tables) |
| **Max** | $14.99 | +~750MB AI libraries | Native + Enhanced + AI |

---

## Basic Tier (Free)

### What it includes (bundled in app, no download):
- Python 3.12 core (minimal, ~40-50MB)
- ocrmac (~5-10MB) — Apple Vision OCR via native framework
- Basic utilities: numpy, pillow, pydantic
- NO heavy dependencies

### What it can do:
- Native PDF extraction (PDFKit)
- Native image OCR (Vision framework)
- Native audio/video metadata (AVFoundation)
- MarkItDown fallback for office formats

### What it cannot do:
- Layout analysis
- Table structure detection
- AI conversion
- Complex document handling

### No additional downloads required

---

## Pro Tier ($9.99)

### What it adds (user downloads once, ~350MB):
**docling-pro-runtime** package includes:
- Docling 2.96.0 (core only, no models)
- docling-core, docling-parse
- Table structure libraries
- Office format handlers: pypdfium2, mammoth, python-pptx, openpyxl
- Native macOS bindings for better performance
- **Explicitly excludes**: torch, mlx, transformers, onnxruntime

### What it can do (in addition to Basic):
- Enhanced PDF conversion with layout analysis
- Table structure detection and extraction
- Complex multi-format document handling
- All Basic tier capabilities

### What it cannot do:
- AI/VLM conversion
- Understand scanned images without OCR

### Download requirement:
- **One-time download**: ~350MB
- **Installed size**: ~350MB (will vary by compression)
- Users see: "Enhanced Conversions · 350 MB (one-time download)"

---

## Max Tier ($14.99)

### What it adds to Pro (user downloads once, ~750MB):
**docling-ai-runtime** package includes:
- torch 2.12.0 (~200MB)
- torchvision 0.27.0
- transformers 5.9.0 (~100MB)
- mlx 0.31.2 (~180MB)
- mlx-metal 0.31.2
- mlx-vlm 0.3.3
- onnxruntime 1.18.0+ (~70MB)
- huggingface_hub 1.17.0
- **Note**: The bundled Granite Docling MLX weights come separately as the "AI model"

### What it can do (in addition to Pro):
- AI/VLM conversion with Granite Docling MLX
- Understand scanned documents
- Complex research document analysis
- Vision-based document understanding

### Download requirements:
- **docling-pro-runtime** (if not already installed): ~350MB
- **docling-ai-runtime**: ~750MB
- **AI model weights** (Granite Docling MLX): ~600MB

### Total for new Max users:
- ~350MB (Pro runtime) + ~750MB (AI runtime) + ~600MB (model weights) = ~1,700MB
- Or if already Pro: ~750MB (AI runtime) + ~600MB (model weights) = ~1,350MB

### In UI, users see:
- Pro users: "Add AI (750 MB)…"
- Max users: "AI for Complex Documents · 600 MB installed"

---

## Asset Breakdown

### ModelAsset enum (what gets downloaded):

```swift
enum ModelAsset: String {
    case pythonRuntime = "python_runtime_pro"    // ~350MB
    case aiLibraries = "ai_libraries"            // ~750MB
    case upmarketAI = "upmarket_ai"              // ~600MB (model weights)
    case layout = "layout"                        // ~20MB (bundled with Enhanced model detection)
}
```

### Tier requirements:

| Asset | Basic | Pro | Max |
|-------|-------|-----|-----|
| pythonRuntime | ❌ | ✅ Required | ✅ Required |
| aiLibraries | ❌ | ❌ | ✅ Required |
| upmarketAI | ❌ | ❌ | ✅ Required |
| layout | ❌ | ✅ Included with Enhanced | ✅ Included with Enhanced |

---

## Build Configuration

### What gets bundled in Upmarket.app (no download):
```
Upmarket.app/
├── Python.framework/
│   └── lib/python3.12/site-packages/
│       ├── ocrmac (~10MB)
│       ├── numpy, pillow, pydantic (basic utils)
│       └── NO docling, NO torch, NO transformers
└── [~50MB total for Python core + minimal libs]
```

### What users download (post-install):

**For Pro users:**
```
~/Library/Application Support/Upmarket/models/
├── python_runtime_pro/        (~350MB)
│   ├── docling/*
│   ├── docling-core/*
│   ├── office format libs
│   └── macOS-optimized bindings
```

**For Max users (Pro + this):**
```
~/Library/Application Support/Upmarket/models/
├── ai_libraries/               (~750MB)
│   ├── torch/*
│   ├── mlx/*
│   ├── transformers/*
│   ├── onnxruntime/*
│   └── huggingface_hub/*
├── upmarket_ai/                (~600MB)
│   └── granite-docling-mlx model weights
```

---

## UI Contract

### Preferences → Conversion tab:

**Section intro (all tiers):**
```
"Download models to unlock enhanced and AI-powered conversion. 
Everything runs on your Mac — nothing is sent to the cloud."
```

**Pro Tier** (Basic users see locked):
```
Name: Enhanced Conversions
Status (idle): "Layout analysis and table extraction · 350 MB (one-time download)"
Status (installed): "Layout analysis and table extraction · 347 MB installed"
Action: "Download" button (or "Upgrade" if locked)
```

**Max Tier** (unlocked only for Max users):
```
Name: AI for Complex Documents
Status (idle): "Understands scanned pages and complex documents · 750 MB (one-time download)"
Status (installed): "Understands scanned pages and complex documents · 742 MB installed"
Action: "Download" button (or "Upgrade" if locked)
```

### Menu bar:
```
Basic → Pro:     "Unlock Enhanced (350 MB)…"
Pro → Max:       "Add AI (750 MB)…"
Max:             "All Features Unlocked"
```

---

## Size Philosophy

- **Shown sizes** are downloaded/installed sizes (post-compression)
- **Pro runtime**: ~350MB covers Docling + office handlers + native bindings
- **AI libraries**: ~750MB covers torch, mlx, transformers, onnxruntime stack
- **Model weights**: ~600MB for Granite Docling MLX weights
- All sizes are "one-time downloads" — no recurring network access

---

## Validation Checklist

Before any build/release:

- [ ] `requirements-pro.txt` only includes Basic + Docling dependencies
- [ ] `requirements-ai.txt` includes torch, mlx, transformers, onnxruntime
- [ ] App bundle contains ONLY Basic tier Python + ocrmac
- [ ] Build script creates two separate downloadable packages
- [ ] ModelAsset sizes reflect actual measured sizes (post-compression)
- [ ] AppTierGate enforces: Pro requires pythonRuntime, Max requires both pythonRuntime + aiLibraries + upmarketAI
- [ ] UI copy matches this document exactly
- [ ] Tests validate tier gating and download availability
