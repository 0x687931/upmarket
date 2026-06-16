# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Upmarket is a macOS App Store app that converts documents (PDF, DOCX, PPTX, XLSX, HTML, images, audio, video) to Markdown. It prefers on-device Apple frameworks and falls back to an embedded CPython + Docling runtime for complex documents. It runs 100% offline — no cloud inference, no API keys.

The product loop: drop or choose a document → watch clear progress → get Markdown → copy/save it → pay once for durable value. Philosophy (see `docs/PROJECT_VISION.md`): Linus-style minimalism + DHH-style coherent monolith. Keep code obvious, small, native-first, debuggable. Avoid protocol forests, speculative abstractions, Redux/TCA-style frameworks, and hidden background magic.

## Build, Test, Run

The single source of truth for build/test is `scripts/ci/gate.sh`. Run from repo root.

- `scripts/ci/gate.sh quick` — normal local/PR gate: static policy checks, unsigned build, effective-plist check, unit tests. **Run this before every PR.** (This is exactly what CI runs.)
- `scripts/ci/gate.sh policy` — static policy checks only (fast).
- `scripts/ci/gate.sh runtime` — rebuild + verify the bundled Python runtime and app package. Use for Python, dependency, entitlement, model, corpus, or packaging changes.
- `scripts/ci/gate.sh minor` (alias `release`) — full release gate without UI automation.
- `scripts/ci/gate.sh major` — release gate **plus** UI automation. Reserve for major candidates / explicit UI changes; it may switch system light/dark appearance.
- `scripts/ci/ensure_python_runtime.sh` — prepares the local (git-ignored) `Upmarket/Python/Python.xcframework` if `gate.sh quick` reports it missing.
- `scripts/dev/run_app.sh` — deterministic local build + ad-hoc-signed sandboxed launch. `--relaunch` to kill an older instance first. CloudKit / App Group capabilities require real signing.

Direct Xcode (when you need a single test or finer control):

```sh
# Project (no .xcworkspace): Upmarket/Upmarket.xcodeproj, scheme "Upmarket"
xcodebuild test -project Upmarket/Upmarket.xcodeproj -scheme Upmarket \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:UpmarketTests/ConversionQueueTests/testSomething
```

Python bridge work: `python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt`. Rebuild the bundled runtime with `scripts/build_python_env.sh`.

## Architecture

Authoritative diagrams: `docs/ARCHITECTURE.md`. Boundary map before moving code: `docs/release/ARCHITECTURE_BOUNDARIES.md` and `docs/release/adr/0001-minimalist-monolith-boundaries.md`.

### Conversion is native-first, with a Python fallback in a separate process

There is **one conversion entry point**: `ConversionQueue.add()` → `ConversionRunner.run()`. A job owns its own progress, result, error, and cancellation state. Routing by file type happens in `ConversionRunner`:

- **Apple-native paths run in-process** inside `Upmarket.app`: PDFKit (digital PDFs), Vision OCR (scanned PDFs/images), Speech (audio), AVFoundation (video/audio metadata), ImageIO (image metadata), NaturalLanguage (post-processing).
- **Python paths run in `UpmarketRuntimeHelper`** — a separate sandboxed process launched **per job**. Docling, MarkItDown, and pdfium live here. A helper crash or hang maps to a typed Swift error and **cannot take down the main app**.

The Swift↔Python boundary is a single funnel: `PythonWorker` → `RuntimeHelperClient` → the `UpmarketRuntimeHelper` process. SwiftUI views never call Python, StoreKit, or file APIs directly.

PDF classification (`NativeDocumentClassifier`) decides digital-text → PDFKit, scanned → Vision, complex → Docling. With AI enabled, multiple pathways run and `MarkdownQualityScorer` selects the best output.

Docling pipelines: Enhanced tier = `StandardPdfPipeline` (layout + table OCR); AI tier = `VlmPipeline` (Granite Docling MLX). Output is always `export_to_markdown()`.

### Layers (`Upmarket/Upmarket/`)

- `Views/` — SwiftUI only. Render state, send actions. No business logic.
- `Services/` — concrete coordinators (singletons injected via `.environmentObject`): `ConversionQueue`, `ConversionRunner`, `PythonWorker`, `RuntimeHelperClient`, `ModelManager`, `StoreManager`, `FileAccessService`, window controllers, native extractors, etc.
- `Domain/` — value types (structs/enums) for shared domain data.
- `Intents/` — App Intents.
- `Design/` — `AppTheme`, button styles (amber/orange design system).

### Targets (schemes in `Upmarket/Upmarket.xcodeproj`)

- **Upmarket** — the SwiftUI app.
- **UpmarketRuntimeHelper** — sandboxed per-job Python host (`Upmarket/UpmarketRuntimeHelper/main.swift`).
- **UpmarketCLI** — command-line conversion entry (`CLIConversionBroker` bridges app ↔ CLI).
- **UpmarketMCP** — MCP server exposing conversion as tools (`UpmarketMCP/`).
- **UpmarketQuickAction** — Finder/Share extension.

### Python (`UpmarketPython/`)

One Swift boundary wraps all of this. `docling_bridge/` (converter, analyser, postprocessor, security) and `models/` (model_manager). Source here is synced into the helper at build time — see `scripts/ci/sync_python_bridge.sh`.

## Architecture Decisions (Do Not Revisit Without Good Reason)

- **SwiftUI only** — no AppKit/NSViewController unless SwiftUI genuinely cannot do it.
- **Native Apple APIs preferred** where practical: PDFKit, Vision, NaturalLanguage, Speech, AVFoundation, ImageIO, StoreKit, OSLog.
- **BeeWare Python-Apple-support** for CPython embedding; **PythonKit** (vendored at `Upmarket/Vendor/PythonKit/`) for interop; **Docling** as the conversion engine.
- **No cloud inference, no Ollama, no Hugging Face at runtime** (`HF_HUB_OFFLINE=1` after model cache). Model download is the only network-dependent setup path.
- App ships lean (Swift only); the Python runtime (~1.3 GB) and model weights (~3–5 GB) are gated post-purchase downloads.

## Key Constraints

- **App Sandbox is always on.** Do not add temporary exceptions or broad filesystem access without a P0 implementation-plan item. Network entitlement (`com.apple.security.network.client`) is only for model download.
- Bundle ID `com.upmarket.app`; App Group `group.com.upmarket.app`. Minimum deployment target macOS 26.0. Python 3.12.
- Models stored in `~/Library/Application Support/Upmarket/models/`; validate before enabling model-backed conversion.
- **Pin ALL Python deps with exact `==`** in `requirements.txt`. Proposed updates go in `requirements-candidate.txt` first. Known conflict: `mlx-vlm` vs `docling-ibm-models` want different `transformers` versions — see `docs/IMPLEMENTATION_PLAN.md`.
- Conversion runs off the main thread; progress flows via async streams to SwiftUI. Target: 10-page PDF < 30s on M1.
- **Diagnostics are privacy-redacted by default.** Never commit model weights, generated runtimes, private documents, credentials, or unredacted diagnostics.
- **User-facing copy must not expose implementation toolkit names** (Python, Docling, internal converter packages) except in licenses or explicit diagnostic previews. This is enforced by `scripts/ci/validate_user_facing_copy.py`.

## Coding Conventions

- No force unwraps — use `guard`/`if let`.
- Comments explain *why* (non-obvious constraints), never *what*.
- Python calls are always async — wrap in `Task { await ... }`.

## Workflow

- **Never commit to main** — always use a worktree. See `~/.claude/WORKTREE_WORKFLOW.md`. This is enforced: a PreToolUse hook (`.claude/settings.json` → `.claude/hooks/require-worktree.sh`) hard-blocks `Edit`/`Write`/`NotebookEdit` and destructive `Bash` (`rm`, `git rm/mv/commit/reset/checkout/...`) whenever the target resolves to the primary checkout or a `main`/`master` HEAD. Create a worktree first: `git worktree add ../upmarket-<task> -b <branch>`.
- PR for every feature; use `.github/PULL_REQUEST_TEMPLATE.md` (summary, release gate, scope, validation, risk review, agent handoff notes). Short imperative commit summaries.
- Before a change is "done": identify the affected release gate in `docs/IMPLEMENTATION_PLAN.md` and run the matching `gate.sh` mode. If validation can't be run, say so explicitly in the handoff.
- Multi-agent work: assign disjoint write sets; only one agent owns a file at a time. Agents read broadly, edit narrowly. See `AGENTS.md` and `docs/release/AGENT_TASK_ORCHESTRATION.md`.

## Key Docs

`docs/ARCHITECTURE.md`, `docs/IMPLEMENTATION_PLAN.md`, `docs/PROJECT_VISION.md`, `docs/BUILD_SHIP_DEPLOY.md`, `docs/RELEASING.md`, `docs/release/` (pipeline, boundaries, ADRs, UI automation policy).
