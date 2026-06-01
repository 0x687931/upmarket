# Repository Guidelines

## Project Vision

Upmarket converts documents to clean Markdown on macOS, privately and reliably. The product loop is: drop or choose a document, watch clear progress, get Markdown, copy/save it, and pay once for durable value.

Follow the project philosophy in `docs/PROJECT_VISION.md`: Linus-style minimalism plus DHH-style coherent monolith. Keep code obvious, small, native-first, and debuggable. Avoid protocol forests, speculative abstractions, Redux/TCA-style frameworks, and hidden background magic unless the implementation plan explicitly calls for them.

## Project Structure

The Xcode project is `Upmarket/Upmarket.xcodeproj`; app source is under `Upmarket/Upmarket/`. Current code is still being stabilized, but the target shape is:

- `Views/`: SwiftUI presentation, visible state, and user gestures.
- `Services/`: concrete coordinators such as conversion, StoreKit, file access, diagnostics, and model management.
- `Domain/`: plain structs/enums once shared models outgrow a single service file.
- `Infrastructure/`: hard runtime adapters such as a future Python helper.
- `UpmarketPython/`: first-party Python bridge and model code, isolated behind one Swift boundary.
- `docs/release/`: release pipeline, task orchestration, and validation policy.

Use `docs/release/ARCHITECTURE_BOUNDARIES.md` as the boundary map before moving code.

Large fixtures and upstream corpus material live in `tests/corpus/`; avoid editing vendored corpus files unless the task is explicitly about corpus validation.

## Core Engineering Rules

- There must be one conversion entry point.
- Queue items must own their own progress, result, error, and cancellation state.
- SwiftUI views render state and send actions; they do not call Python, StoreKit, or file APIs directly.
- Python interaction must go through one worker boundary.
- Native Apple APIs are preferred where practical: `PDFKit`, `Vision`, `NaturalLanguage`, `StoreKit`, `OSLog`, `AVFoundation`, `ImageIO`.
- Runtime conversion must not require cloud access. Model download is the only expected network-dependent conversion setup path.
- Diagnostics must be privacy-redacted by default.
- User-facing UI, errors, onboarding, support copy, and App Store text must not expose implementation toolkit names such as Python or internal converter packages except in licenses or explicit diagnostic previews.

## Build, Test, and Development Commands

- `open Upmarket/Upmarket.xcodeproj` opens the app in Xcode.
- `xcodebuild -project Upmarket/Upmarket.xcodeproj -scheme Upmarket -destination 'platform=macOS' build` builds the app.
- `xcodebuild -project Upmarket/Upmarket.xcodeproj -scheme Upmarket -destination 'platform=macOS' test -only-testing:UpmarketTests` runs unit tests for normal implementation work.
- `xcodebuild -project Upmarket/Upmarket.xcodeproj -scheme Upmarket -destination 'platform=macOS' test -only-testing:UpmarketUITests` runs UI automation; reserve this for release candidates or explicit UI changes because it may switch light/dark appearance.
- `python3 -m venv .venv && . .venv/bin/activate && pip install -r requirements.txt` prepares Python dependencies for local bridge work.
- `scripts/build_python_env.sh` rebuilds the bundled Python runtime.

## Testing and Release Discipline

Before a change is considered done, identify the affected release gate in `docs/IMPLEMENTATION_PLAN.md`. Use `docs/release/RELEASE_PIPELINE.md` for required hooks and `docs/release/AGENT_TASK_ORCHESTRATION.md` for scoped multi-agent work.

At minimum, run the relevant Xcode build/test command. For release, Python, sandbox, entitlement, model, or CI changes, add or run the matching hook script once it exists. If validation cannot be run, state that explicitly in the handoff.

## Agent Task Rules

Use GitHub issues or checklist items for agent work. Every task needs objective, scope, non-goals, acceptance criteria, release gate, and risk area. Assign disjoint write sets before launching multiple agents. Only one agent owns a file at a time.

Agents may read broadly but must edit narrowly. The main Codex session integrates results and resolves conflicts. Do not mix unrelated cleanup into a scoped task.

## Commit and PR Guidelines

Use short imperative commit summaries, for example `Fix shelf queue state` or `Add plist validation hook`. PRs must include summary, release gate, scope, validation, risk review, and agent handoff notes. Use `.github/PULL_REQUEST_TEMPLATE.md`.

## Security and Configuration

Keep App Sandbox enabled. Do not add temporary exceptions or broad filesystem access without a P0 implementation-plan item. Never commit model weights, generated runtimes, private documents, credentials, or unredacted diagnostics. Store models under `~/Library/Application Support/Upmarket/models/` and validate them before enabling model-backed conversion.
