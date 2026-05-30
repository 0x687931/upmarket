# Upmarket — Claude Code Instructions

## Project Overview

Upmarket is a macOS App Store app that converts documents (PDF, DOCX, PPTX, etc.) to Markdown using on-device AI. It embeds CPython + Docling and runs 100% offline on Apple Silicon via Metal (MPS + MLX).

## Architecture Decisions (Do Not Revisit Without Good Reason)

- **SwiftUI only** — no AppKit, no NSViewController unless SwiftUI cannot do it
- **BeeWare Python-Apple-support** for CPython embedding (not Pyodide, not subprocess)
- **PythonKit** for Swift ↔ Python interop
- **Docling** as the conversion engine (MIT licensed)
- **PyTorch/MPS** for layout/table models; **MLX** for SmolDocling VLM
- **In-app download** for models (v1); Background Assets framework (v2)
- **No cloud inference** — models always run locally
- **No Ollama, no Hugging Face at runtime** — `HF_HUB_OFFLINE=1` after model cache

## Key Constraints

### App Store
- App Sandbox must be enabled at all times
- Network entitlement (`com.apple.security.network.client`) only for model download
- Models stored in `~/Library/Application Support/Upmarket/models/`
- Privacy manifest required (`PrivacyInfo.xcprivacy`)
- Bundle ID: `com.upmarket.app`
- Minimum deployment target: macOS Ventura 13.3

### Python Environment
- Python 3.12 (matches BeeWare support)
- All dependencies must be bundled — no pip at runtime
- Pin ALL dependency versions in `requirements.txt`
- Known conflict: `mlx-vlm` and `docling-ibm-models` require different `transformers` versions — see IMPLEMENTATION_PLAN.md

### Performance
- Conversion must run on a background thread — never block the main thread
- Progress updates via `AsyncStream` published to SwiftUI
- Target: 10-page PDF converts in < 30 seconds on M1

## Project Structure

```
Upmarket/               # Xcode SwiftUI app target
  Views/                # SwiftUI views only — no business logic
  ViewModels/           # @MainActor ObservableObject classes
  Models/               # Value types (structs/enums) for domain data
  Services/             # PythonBridge, ConversionService, ModelManager
  Python/               # BeeWare runtime (not in git — see scripts/)
  Resources/            # Bundled assets
UpmarketPython/         # Python source (bundled into app at build time)
  docling_bridge/       # converter.py, progress reporting
  models/               # model_manager.py, download utilities
scripts/                # build_python_env.sh, strip_stdlib.sh
docs/                   # IMPLEMENTATION_PLAN.md and other docs
```

## Coding Conventions

- SwiftUI views are dumb — all logic in ViewModels or Services
- Services are singletons injected via `.environmentObject`
- Python calls are always async — wrap in `Task { await ... }`
- No force unwraps — use guard/if let
- No comments explaining what code does — only why (non-obvious constraints)

## Workflow

- Never commit to main — always use a worktree
- PR for every feature
- See `~/.claude/WORKTREE_WORKFLOW.md` for full process

## Implementation Plan

Full plan: `docs/IMPLEMENTATION_PLAN.md`

Current phase: **Phase 1 — Project Scaffold**
