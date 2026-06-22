# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Upmarket is a macOS App Store app that converts documents (PDF, DOCX, PPTX, XLSX, HTML, EPUB, images, audio) to Markdown. Conversion is **100% native Swift** — Apple frameworks (PDFKit, Vision, Speech, AVFoundation, ImageIO), the vendored SwiftOfficeMarkdown engine for Office, libxml2 for HTML, and on-device Granite-Docling (mlx-swift) for the AI tier. There is no Python runtime. It runs 100% offline — no cloud inference, no API keys.

The product loop: drop or choose a document → watch clear progress → get Markdown → copy/save it → pay once for durable value. Philosophy (see `docs/PROJECT_VISION.md`): Linus-style minimalism + DHH-style coherent monolith. Keep code obvious, small, native-first, debuggable. Avoid protocol forests, speculative abstractions, Redux/TCA-style frameworks, and hidden background magic.

## Build, Test, Run

The single source of truth for build/test is `scripts/ci/gate.sh`. Run from repo root.

- `scripts/ci/gate.sh quick` — normal local/PR gate: static policy checks, unsigned build, effective-plist check, unit tests. **Run this before every PR.** (This is exactly what CI runs.)
- `scripts/ci/gate.sh policy` — static policy checks only (fast).
- `scripts/ci/gate.sh runtime` — rebuild + verify the packaged app (no-Python-embed guard, entitlements, plist, bundled CLI/MCP). Use for entitlement, model, corpus, or packaging changes.
- `scripts/ci/gate.sh minor` (alias `release`) — full release gate without UI automation.
- `scripts/ci/gate.sh major` — release gate **plus** UI automation. Reserve for major candidates / explicit UI changes; it may switch system light/dark appearance.
- `scripts/dev/run_app.sh` — deterministic local build + ad-hoc-signed sandboxed launch. `--relaunch` to kill an older instance first. CloudKit / App Group capabilities require real signing.

The build needs `-skipMacroValidation` (for the mlx-swift-lm Swift macro); `gate.sh` and `run_app.sh` already pass it. CI scripts are written in `python3` (system Python, as a scripting language) — that is unrelated to the removed conversion runtime.

Direct Xcode (when you need a single test or finer control):

```sh
# Project (no .xcworkspace): Upmarket/Upmarket.xcodeproj, scheme "Upmarket"
xcodebuild test -project Upmarket/Upmarket.xcodeproj -scheme Upmarket \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:UpmarketTests/ConversionQueueTests/testSomething
```

## Architecture

Authoritative diagrams: `docs/ARCHITECTURE.md`. Boundary map before moving code: `docs/release/ARCHITECTURE_BOUNDARIES.md` and `docs/release/adr/0001-minimalist-monolith-boundaries.md`.

### Conversion is native-only, in-process

There is **one conversion entry point**: `ConversionQueue.add()` → `ConversionRunner.run()`. A job owns its own progress, result, error, and cancellation state. Routing by file type happens in `ConversionRunner`, and every engine runs **in-process** inside `Upmarket.app`:

- **PDFKit** (digital PDFs), **Vision OCR + adaptive table banding** (scanned/complex PDFs and images), **Speech** (audio), **AVFoundation/ImageIO** (media/image metadata), **NaturalLanguage** (post-processing).
- **SwiftOfficeMarkdown** (`OfficeToMarkdown`) for DOCX/XLSX/PPTX + legacy binary Office; **NativeHTMLConverter** (libxml2) for HTML; **NativeTextConverter** for TXT/MD/CSV; **NativeEPUBConverter** (ZipReader + OPF spine + HTML walker) for EPUB.
- **Native Granite-Docling (mlx-swift)** for the AI tier — `UpmarketVLM.GraniteDoclingEngine`, rendering PDF pages and parsing DocTags to Markdown.

PDF classification (`NativeDocumentClassifier`) decides digital-text → PDFKit, scanned/complex → Vision; `NativeDocumentClassifier.recommendedEngine` gates the native Granite path to clean typed Latin/simplified-Chinese docs. The quality-selected PDF path runs PDFKit + Vision and `MarkdownQualityScorer` picks the best output. SwiftUI views never call conversion engines, StoreKit, or file APIs directly.

### Layers (`Upmarket/Upmarket/`)

- `Views/` — SwiftUI only. Render state, send actions. No business logic.
- `Services/` — concrete coordinators (singletons injected via `.environmentObject`): `ConversionQueue`, `ConversionRunner`, `ModelManager`, `StoreManager`, `FileAccessService`, native converters/extractors, window controllers, etc.
- `Domain/` — value types (structs/enums) for shared domain data.
- `Intents/` — App Intents.
- `Design/` — `AppTheme`, button styles (amber/orange design system).

### Targets (schemes in `Upmarket/Upmarket.xcodeproj`)

- **Upmarket** — the SwiftUI app.
- **UpmarketCLI** — command-line conversion entry (`CLIConversionBroker` bridges app ↔ CLI). PDF/image/text native; Office/EPUB route to the app.
- **UpmarketMCP** — MCP server exposing conversion as tools (`UpmarketMCP/`).
- **UpmarketQuickAction** — Finder/Share extension.

### Vendored Swift packages (`Upmarket/Vendor/`, `Vendor/`)

- **`UpmarketVLM`** — wraps mlx-swift-lm to load and run Granite-Docling (`GraniteDoclingEngine`, `DocTags` → Markdown parser).
- **`SwiftOfficeMarkdown`** — first-party OOXML/legacy-binary Office engine (`ZipReader`, part parsers).

## Architecture Decisions (Do Not Revisit Without Good Reason)

- **SwiftUI only** — no AppKit/NSViewController unless SwiftUI genuinely cannot do it.
- **Native Apple APIs preferred** where practical: PDFKit, Vision, NaturalLanguage, Speech, AVFoundation, ImageIO, StoreKit, OSLog.
- **No Python runtime.** Conversion is native Swift end-to-end; the embedded CPython + Docling/MarkItDown runtime and the `UpmarketRuntimeHelper` process were removed. Do not reintroduce them (enforced by `scripts/ci/validate_architecture_boundaries.py`).
- **Granite-Docling runs via mlx-swift** (`UpmarketVLM`), not Python MLX.
- **No cloud inference, no Ollama, no Hugging Face at runtime** (`HF_HUB_OFFLINE=1` after model cache). Model download is the only network-dependent setup path.
- App ships lean; only the Max-tier Granite model weights (`granite_docling`, ~600 MB) are a gated post-purchase download.

## Key Constraints

- **App Sandbox is always on.** Do not add temporary exceptions or broad filesystem access without a P0 implementation-plan item. Network entitlement (`com.apple.security.network.client`) is only for model download.
- Bundle ID `com.upmarket.app`; App Group `group.com.upmarket.app`. Minimum deployment target macOS 26.0.
- Debug models are stored in `~/Library/Application Support/Upmarket/models/<model-key>/`.
  Release/TestFlight models are Apple-hosted managed asset packs; resolve their process-lifetime
  URLs through `AssetPackManager` and never persist those URLs.
- **Swift package dependencies are pinned in `Package.resolved`** (committed). The app's only local packages are first-party (`UpmarketVLM`, `SwiftOfficeMarkdown`).
- Conversion runs off the main thread; progress flows via async streams to SwiftUI. Target: 10-page PDF < 30s on M1.
- **Diagnostics are privacy-redacted by default.** Never commit model weights, generated runtimes, private documents, credentials, or unredacted diagnostics.
- **User-facing copy must not expose implementation toolkit names** (Python, Docling, internal converter packages) except in licenses or explicit diagnostic previews. This is enforced by `scripts/ci/validate_user_facing_copy.py`.

## Coding Conventions

- No force unwraps — use `guard`/`if let`.
- Comments explain *why* (non-obvious constraints), never *what*.
- Conversion and model-load calls are async — wrap in `Task { await ... }`.

## Workflow

- **Never commit to main** — always use a worktree. See `~/.claude/WORKTREE_WORKFLOW.md`. This is enforced: a PreToolUse hook (`.claude/settings.json` → `.claude/hooks/require-worktree.sh`) hard-blocks `Edit`/`Write`/`NotebookEdit` and destructive `Bash` (`rm`, `git rm/mv/commit/reset/checkout/...`) whenever the target resolves to the primary checkout or a `main`/`master` HEAD. Create a worktree first: `git worktree add ../upmarket-<task> -b <branch>`.
- **Prune worktrees after their PR merges** — each worktree builds into its own repo-local `build/DerivedData` (2–10 GB), so stale worktrees silently erode disk. `git worktree remove <path>` clears the checkout and its `build/`. A `SessionStart` hook (`.claude/hooks/disk-watch.sh`) warns when worktree build caches exceed 8 GB.
- PR for every feature; use `.github/PULL_REQUEST_TEMPLATE.md` (summary, release gate, scope, validation, risk review, agent handoff notes). Short imperative commit summaries.
- Before a change is "done": identify the affected release gate in `docs/IMPLEMENTATION_PLAN.md` and run the matching `gate.sh` mode. If validation can't be run, say so explicitly in the handoff.
- Multi-agent work: assign disjoint write sets; only one agent owns a file at a time. Agents read broadly, edit narrowly. See `AGENTS.md` and `docs/release/AGENT_TASK_ORCHESTRATION.md`.

## Key Docs

`docs/ARCHITECTURE.md`, `docs/IMPLEMENTATION_PLAN.md`, `docs/PROJECT_VISION.md`, `docs/BUILD_SHIP_DEPLOY.md`, `docs/RELEASING.md`, `docs/release/` (pipeline, boundaries, ADRs, UI automation policy).
