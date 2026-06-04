# Panic Review Remediation Plan

Date: 2026-06-03

This plan turns the Steven Frank / Panic-style product review into scoped work
packages with validation gates. It is intentionally conservative about
architecture: every conversion-facing feature must still enter through
`ConversionQueue`, Python/model work must stay behind the runtime helper, and
normal user-facing UI must not expose internal converter toolkit names.

This document is a planning artifact. If any item below is promoted to P0, add
or update the matching task in `docs/release/p0_task_registry.json` and
`docs/IMPLEMENTATION_PLAN.md`, then run:

```sh
scripts/ci/validate_task_registry.py
scripts/ci/validate_p0_plan_sync.py
```

## Local Audit Snapshot

The review is directionally useful, but several concrete claims are stale
relative to the current source tree.

| Review item | Current source status | Planning action |
| --- | --- | --- |
| Passive shelf actions always visible | Already present in `ShelfItemView.persistentActions` | Keep and add visual/manual criteria if touched |
| Menu bar badge dot | Already present in `MenuBarIconView` | Keep and add visual/manual criteria if touched |
| Dropdown gradient banner | Already present in `MenuBarDropdown.headerBanner` | Treat as implemented, not a new build task |
| Shelf card width spec | Still fixed at 64 pt | Defer behind higher-value trust fixes |
| Onboarding 4-act cinematic flow | Not implemented; current flow is 3 steps | v1.1 UI spec closure unless owner promotes |
| Single-click shelf copy | Still present in `handleSingleClick()` | Fix in first UI trust pass |
| Liquid glass state tint | Not wired; `LiquidGlassBackground` has no state inputs | Fix in first UI trust pass |
| Stalled job cancel affordance | Cancel remains hover-only for running cards | Fix in first UI trust pass |
| Output pathway/provenance badge | `ConversionOutput.pipeline` exists, but no selected pathway or visible badge | Fix in provenance pass |
| Runtime conversion progress | Generic heartbeat exists; no fractional conversion progress | Build a progress event contract |
| Dependency drift bot | Already present through nightly upstream workflow and `watch_upstream.py` | Validate only; do not rebuild |
| Persistent history | Session-only history popover exists; no restart persistence | Build history store and search |
| CLI | No CLI target found | Build after output/provenance contract is stable |
| Watch folder | No watch-folder service found | Build after history and CLI |
| Structured output | No frontmatter/JSON output mode found | Build before CLI default formats |
| Nova extension | No Nova extension found | Build after CLI |

## Priority Decision

Recommended release posture:

1. **Panic Quality Patch 1 - UI trust and provenance.** Ship before broad beta.
   It fixes clipboard surprise, stalled-job confusion, state-aware glass, and
   pathway visibility without new product surfaces.
2. **Panic Quality Patch 2 - persistent history and structured output.** Promote
   if v1.0 is meant to be a trusted daily workflow tool. Otherwise treat as
   v1.1, but do not start CLI or Nova before this data contract exists.
3. **Panic Integration Track - CLI, watch folders, Nova.** High leverage, but
   each adds a new entry surface. Require an ADR before implementation.
4. **Spec Closure Track - shelf widths, corner guides, 4-act onboarding.** Useful
   craft work, but lower risk than history/CLI and should not displace core
   reliability unless the owner explicitly prioritizes launch polish.

## Implementation Progress

| Package | Status | Notes |
| --- | --- | --- |
| PR-1 UI Trust Pass | Implemented | Clipboard surprise, stalled cancel visibility, and state glass tint are shipped. |
| PR-2 Conversion Provenance Badge | Implemented | Result, diagnostics, and history carry product-level pathway labels. |
| PR-3 Persistent Conversion History | Implemented | History is stored as clearable local JSON with search/copy UI. |
| PR-4 Structured Output Mode | Implemented | Markdown remains raw internally; frontmatter/JSON format at output boundaries. |
| PR-5 Runtime Progress Event Channel | Implemented | Helper progress events advance queue progress without replacing heartbeat liveness. |
| PR-6 `upmarket` CLI | Implemented | URL/App Group handoff keeps conversion inside the app; CLI target builds as `upmarket`. |
| PR-7 Watch Folder Support | Implemented | Opt-in watched folders enqueue through `ConversionQueue`. |
| PR-8 Nova Extension | Implemented | Thin Nova wrapper calls the CLI and has a manifest validator. |
| PR-9 Dependency Watch Hardening | Implemented | Workflow/report contract now has a regression validator. |
| PR-10 UI Spec Closure | Implemented as docs decision | Remaining cinematic/spec polish is explicitly v1.1. |

## Work Package PR-1 - UI Trust Pass

Objective: remove surprising and confusing interactions in the shelf and make
the glass background respond to conversion state.

Scope:

- `Upmarket/Upmarket/Views/ShelfView.swift`
- `Upmarket/Upmarket/Views/LiquidGlass.swift`
- `Upmarket/UpmarketTests/ConversionQueueTests.swift` if state helpers change
- `Upmarket/UpmarketUITests/UpmarketUITests.swift` for visible UI regressions
- `docs/UI_VISUAL_CRITERIA_UI2.md` if visual criteria are updated

Non-goals:

- Do not redesign the shelf layout.
- Do not implement progressive 96 pt / 72 pt card widths in this pass.
- Do not change queue ordering, pricing, StoreKit, or conversion routing.

Implementation:

- Change shelf single-click from copy to select/focus. Add a selected-card visual
  state and keep copy behind the visible copy button and context menu.
- Keep double-click opening the saved Markdown result.
- Show the running cancel action when `isStalled` is true, even without hover.
- Extend the glass treatment with state parameters or wrap it with a state tint:
  drag hover gets a faint accent fill, conversion gets an accent bloom, and any
  terminal error gets a faint red tint.
- Keep current passive-card action buttons always visible.

Acceptance:

- Single-clicking a completed shelf item never writes to the pasteboard.
- Copy button still copies Markdown and still shows a visible copied state.
- Double-click still opens the Markdown in the default editor.
- A stalled running card shows cancel without hover.
- Shelf glass visibly changes for drag hover, active conversion, and error.
- UI still compiles and works on macOS 13.3+ with symbol-effect availability
  guards.

Validation:

```sh
scripts/ci/gate.sh quick
scripts/ci/gate.sh major
```

Manual validation:

- Complete a conversion, put unique text on the clipboard, single-click the
  result card, and verify the clipboard is unchanged.
- Hover and non-hover a stalled job fixture or injected slow runner and verify
  cancel remains visible once stalled.
- Capture light and dark screenshots of idle, converting, drag-targeted, and
  failed shelf states.

Release gate: Gate C stability and diagnostics, plus UI automation for explicit
UI changes.

Risk: UX, accessibility, regression in shelf interactions.

## Work Package PR-2 - Conversion Provenance Badge

Objective: surface the selected conversion tier/pathway in both the result UI
and diagnostics without exposing implementation package names in normal copy.

Scope:

- `Upmarket/Upmarket/Domain/ConversionResult.swift`
- `Upmarket/Upmarket/Services/ConversionRunner.swift`
- `Upmarket/Upmarket/Services/RuntimeHelperClient.swift`
- `Upmarket/UpmarketRuntimeHelper/main.swift`
- `Upmarket/Upmarket/Views/ContentView.swift`
- `Upmarket/UpmarketTests/MarkdownQualityScorerTests.swift`
- `Upmarket/UpmarketTests/PythonBridgeTests.swift`
- `Upmarket/UpmarketTests/ConversionQueueTests.swift`

Non-goals:

- Do not add a user-selectable engine picker.
- Do not mention internal converter package names in normal UI.
- Do not change quality scoring weights in this pass.

Implementation:

- Change `Pipeline.displayName` so `.fast` returns `Fast`.
- Add a product-level `selectedPathway` or `pathway` field to
  `ConversionOutput`. Suggested values: `pdfKit`, `visionOCR`, `speech`,
  `metadata`, `enhanced`, `ai`. Keep display mapping product-level:
  `Fast`, `Enhanced`, `AI`.
- When `MarkdownQualityScorer.best(...)` chooses a candidate, preserve the
  selected label in the returned output.
- Keep helper DTO compatibility by defaulting missing pathway data to the
  existing `pipeline`.
- Add a small capsule badge in the bottom-right of the result area, not only in
  the toolbar. It should read `Fast`, `Enhanced`, or `AI`.
- Include pathway in redacted diagnostics and history records, but not full
  local paths or document contents.

Acceptance:

- Native fast PDF output displays a `Fast` badge.
- Enhanced/helper output displays an `Enhanced` badge.
- AI output displays an `AI` badge.
- Quality-selected PDF conversion records which candidate won.
- Existing helper responses without a pathway field still decode.
- Diagnostics can include pathway/tier without exposing internal package names.

Validation:

```sh
scripts/ci/gate.sh quick
scripts/ci/validate_user_facing_copy.py
```

Manual validation:

- Convert one fast digital PDF and one enhanced-supported document, then verify
  the result badge, history metadata if PR-3 is also present, and diagnostic
  preview wording.

Release gate: Gate B conversion reliability and Gate C diagnostics.

Risk: DTO compatibility, user-facing copy policy, test fixture churn.

## Work Package PR-3 - Persistent Conversion History

Objective: preserve completed conversions across app restarts and add a usable
search surface without mixing historical records into active queue state.

Scope:

- New `Upmarket/Upmarket/Domain/ConversionHistoryRecord.swift`
- New `Upmarket/Upmarket/Services/ConversionHistoryStore.swift`
- `Upmarket/Upmarket/Services/ConversionQueue.swift`
- `Upmarket/Upmarket/Views/MenuBarDropdown.swift`
- `Upmarket/Upmarket/Views/PreferencesView.swift`
- `Upmarket/UpmarketTests/**`
- `docs/release/STORAGE_VALIDATION.md`
- `docs/public/privacy.md` if privacy wording changes

Non-goals:

- Do not persist passwords, full source paths, security-scoped bookmarks, or
  unredacted diagnostics.
- Do not restore every historical item into the shelf by default.
- Do not add iCloud sync or cloud backup.

Implementation:

- Store local JSON records under
  `~/Library/Application Support/Upmarket/History/`.
- Use a versioned `ConversionHistoryRecord` with:
  `id`, `createdAt`, `sourceDisplayName`, `sourceExtension`, `title`, `format`,
  `pages`, `wordCount`, `pipeline`, `selectedPathway`, and `markdown`.
- Write records atomically on successful conversion completion.
- Add a Preferences control for clear history and, if the owner wants the
  strongest privacy posture, a "Keep conversion history" toggle.
- Add a History panel/popover reachable from the menu bar dropdown with
  `NSSearchField`-style filtering by filename, title, date, and content snippet.
- Keep shelf focused on current work. If recent completed jobs must reappear in
  the shelf, restore only the most recent N as explicit completed stubs and mark
  them visually as historical.
- Exclude stored Markdown/history payloads from support bundles by default.

Acceptance:

- A completed conversion remains available after quit and relaunch.
- History search finds records by source display name, title, and content
  snippet.
- Copy from history works.
- Clear history deletes stored JSON records.
- Diagnostic/support preview does not include stored Markdown unless a future
  explicit user opt-in is added.
- Corrupt history JSON is ignored or quarantined without crashing launch.

Validation:

```sh
scripts/ci/gate.sh quick
scripts/ci/validate_user_facing_copy.py
```

Focused tests:

- `ConversionHistoryStoreTests.testAtomicWriteAndLoad`
- `ConversionHistoryStoreTests.testCorruptRecordDoesNotCrashLoad`
- `ConversionHistoryStoreTests.testClearHistoryRemovesRecords`
- `ConversionQueueTests.testSuccessfulJobPersistsHistoryRecord`
- UI test for opening History and copying a record

Manual validation:

- Convert a fixture, quit Upmarket, relaunch, search History, copy result, and
  clear history.
- Inspect Application Support and verify no passwords or full source paths are
  stored.

Release gate: Gate B conversion reliability, Gate C diagnostics, Gate E privacy.

Risk: privacy, storage correctness, launch-time robustness.

## Work Package PR-4 - Structured Output Mode

Objective: make Upmarket useful for developer, RAG, and LLM workflows by adding
frontmatter and JSON output modes while keeping Markdown as the default.

Scope:

- New `Upmarket/Upmarket/Services/OutputFormatter.swift`
- `Upmarket/Upmarket/Domain/ConversionResult.swift`
- `Upmarket/Upmarket/Services/ConversionRunner.swift`
- `Upmarket/Upmarket/Views/PreferencesView.swift`
- `Upmarket/Upmarket/Intents/UpmarketIntents.swift`
- Future CLI target from PR-6
- `Upmarket/UpmarketTests/**`

Non-goals:

- Do not change the default output from plain Markdown.
- Do not include full local source paths in frontmatter or JSON.
- Do not expose implementation package names.

Implementation:

- Add `OutputMode`: `markdown`, `markdownWithFrontmatter`, `json`.
- Add `ConversionMetadata` derived from existing output plus
  `DocumentIntelligence` and `ComplexityAdvice` where available.
- Format frontmatter with stable YAML-safe escaping:

```yaml
---
title: "Q3 Financial Report"
source: "report.pdf"
converted: "2026-06-03T00:00:00Z"
language: "en"
type: "financial"
pipeline: "enhanced"
word_count: 4821
---
```

- Add JSON output with a stable schema:

```json
{
  "title": "Q3 Financial Report",
  "markdown": "...",
  "metadata": {
    "source": "report.pdf",
    "pipeline": "enhanced",
    "word_count": 4821
  }
}
```

- Apply formatting at save/copy/intent/CLI boundaries, not inside the core
  converter. `ConversionOutput.markdown` should remain raw Markdown.

Acceptance:

- Default UI copy/save still returns raw Markdown.
- Frontmatter mode includes no full local path.
- JSON mode is valid JSON for arbitrary Markdown content.
- App Intent and CLI can request an output mode without duplicating conversion.
- History records store raw Markdown plus metadata, then format on copy/export.

Validation:

```sh
scripts/ci/gate.sh quick
```

Focused tests:

- YAML escaping for quotes, newlines, and missing metadata.
- JSON encoding for large Markdown and Unicode text.
- App Intent output-mode behavior once intent parameter is added.

Release gate: Gate B conversion reliability and Gate E privacy.

Risk: output compatibility, schema stability, privacy.

## Work Package PR-5 - Runtime Progress Event Channel

Objective: replace flat long-running progress with real stage/fraction updates
from advanced/model conversion while preserving helper isolation.

Scope:

- `Upmarket/Upmarket/Domain/ConversionJob.swift`
- `Upmarket/Upmarket/Services/ConversionQueue.swift`
- `Upmarket/Upmarket/Services/ConversionRunner.swift`
- `Upmarket/Upmarket/Services/PythonWorker.swift`
- `Upmarket/Upmarket/Services/RuntimeHelperClient.swift`
- `Upmarket/UpmarketRuntimeHelper/main.swift`
- `UpmarketPython/**`
- `Upmarket/UpmarketTests/PythonBridgeTests.swift`
- `Upmarket/UpmarketTests/ConversionQueueTests.swift`

Non-goals:

- Do not allow network during conversion.
- Do not remove heartbeat liveness.
- Do not add a hard timeout for legitimate long AI conversions.

Implementation:

- Replace `ProgressHandler = (ConversionStage) -> Void` with a small
  `ConversionProgress` value carrying `stage`, optional `fraction`, and optional
  product-level message.
- Keep a compatibility helper for stage-only updates from native paths.
- Extend runtime helper stdout event parsing to recognize:

```json
{"event":"progress","stage":"python","fraction":0.42,"message":"Processing"}
```

- Keep the final response as the only non-event JSON line. Events must never be
  recorded as response lines.
- If Python libraries cannot emit granular progress yet, emit coarse events
  around known bridge phases first, then extend library-specific callbacks later.
- Continue using heartbeat events for liveness and stalled detection.

Acceptance:

- Helper can emit heartbeat, progress events, and final response in one stdout
  stream without invalid response parsing.
- Queue progress advances inside the Python band instead of staying flat.
- Stalled detection still works when no heartbeat or progress arrives.
- Events contain product-level stage names only and no document text or paths.

Validation:

```sh
scripts/ci/gate.sh quick
scripts/ci/gate.sh runtime
```

Focused tests:

- Fake helper emits progress events before final output.
- Fake helper emits malformed event and still fails safely.
- Liveness monitor terminates a helper that stops heartbeating.
- AI/model long-run manual test shows visible progress movement.

Release gate: Gate B AI-path validation and Gate C stability.

Risk: helper IPC compatibility, concurrency, false stalled states.

## Work Package PR-6 - `upmarket` CLI

Objective: provide a terminal and agent-friendly conversion command without
creating a second conversion engine.

Scope:

- New command-line target `upmarket`
- New ADR under `docs/release/adr/`
- `Upmarket/Upmarket.xcodeproj/project.pbxproj`
- `Upmarket/Upmarket/Services/ConversionQueue.swift` only if a broker hook is
  required
- `Upmarket/Upmarket/Intents/UpmarketIntents.swift`
- `Upmarket/UpmarketTests/**`
- Shell completion/install docs if shipped outside the app bundle

Non-goals:

- Do not duplicate `ConversionRunner` in a separate unsupervised binary.
- Do not bypass StoreKit/programmatic conversion authorization.
- Do not weaken sandbox file access.
- Do not require cloud services.

Implementation decision required:

- Add an ADR choosing the bridge. Preferred candidates:
  - App Intent bridge for simplest first version.
  - App Group request/result files plus URL scheme launch for progress and file
    output.
  - XPC broker if bidirectional progress is required and App Store packaging
    permits it cleanly.
- CLI syntax:

```sh
upmarket convert input.pdf -o output.md
upmarket convert input.pdf --ai --format json
upmarket convert input.pdf --format frontmatter
```

- The CLI should report clear exit codes:
  `0 success`, `2 input rejected`, `3 purchase required`, `4 AI unavailable`,
  `5 conversion failed`, `6 output write failed`.
- Installation should be explicit and reversible. If distributed through the app,
  Preferences can offer "Install Command Line Tool..." rather than silently
  writing into `/usr/local/bin`.

Acceptance:

- CLI conversion consumes the same authorization path as App Intents.
- CLI output matches UI copy/save output for the same mode.
- `--ai` fails clearly when AI is unavailable and does not consume credit.
- Output writes are atomic and never overwrite without explicit `--force`.
- No full source path is printed unless the user requests verbose diagnostics.

Validation:

```sh
scripts/ci/gate.sh quick
```

Additional validation after target exists:

```sh
xcodebuild -project Upmarket/Upmarket.xcodeproj -scheme upmarket -destination 'platform=macOS,arch=arm64' build
upmarket convert tests/corpus/<fixture>.pdf -o /tmp/upmarket-fixture.md
```

Release gate: Gate A packaging, Gate B conversion reliability, Gate D if
authorization or product behavior changes, Gate E privacy/listing copy if CLI is
advertised.

Risk: App Store packaging, sandbox handoff, new product surface.

## Work Package PR-7 - Watch Folder Support

Objective: let users opt into folder-based background conversion without hidden
or surprising behavior.

Scope:

- New `Upmarket/Upmarket/Services/WatchedFolderService.swift`
- `Upmarket/Upmarket/Services/FileAccessService.swift`
- `Upmarket/Upmarket/Views/PreferencesView.swift`
- `Upmarket/Upmarket/Services/ConversionQueue.swift`
- `Upmarket/UpmarketTests/**`
- `docs/release/STORAGE_VALIDATION.md`

Non-goals:

- Do not watch folders by default.
- Do not recursively process entire home directories.
- Do not run unlimited parallel conversions.
- Do not persist broad raw paths without security-scoped bookmarks.

Implementation:

- Add Preferences UI for opt-in watched folders, output location, include/exclude
  patterns, and notification behavior.
- Persist selected folders as security-scoped bookmarks.
- Use FSEvents for directory monitoring or `DispatchSource` for a narrow
  directory descriptor if it proves reliable enough.
- Debounce file-created/modified events and only enqueue stable files.
- Enqueue through `ConversionQueue`.
- Save outputs according to explicit user preference: same folder, configured
  output folder, or history-only.

Acceptance:

- Adding a watched folder requires explicit user selection.
- Dropping a supported file into the watched folder enqueues exactly one job.
- Unsupported files are ignored or recorded as actionable failures according to
  user preference.
- Removing a watched folder stops monitoring.
- App restart resumes watches only for valid bookmarks.

Validation:

```sh
scripts/ci/gate.sh quick
scripts/ci/gate.sh minor
```

Manual validation:

- Local folder, iCloud downloaded folder, external drive, and read-only output
  folder cases from `STORAGE_VALIDATION.md`.

Release gate: Gate B conversion reliability, Gate C stability, Gate E privacy.

Risk: sandbox bookmarks, duplicate events, background UX.

## Work Package PR-8 - Nova Extension

Objective: integrate with Panic's Nova after the CLI exists.

Scope:

- New Nova extension directory after CLI is stable
- CLI invocation docs
- Optional app docs/screenshots

Non-goals:

- Do not build the Nova extension before `upmarket convert` works.
- Do not duplicate conversion logic in JavaScript.
- Do not require the extension to inspect private documents beyond the selected
  file.

Implementation:

- Add file context command "Convert to Markdown".
- Call `upmarket convert` with the selected file.
- Show result in a sidebar or insert result at the active editor cursor.
- Surface CLI exit errors as Nova notifications.

Acceptance:

- Nova command converts a selected supported file.
- Insert-at-cursor and copy result both work.
- AI unavailable and purchase-required errors are clear.

Validation:

- Manual Nova extension test on a local fixture.
- CLI validation from PR-6 remains the hard gate.

Release gate: v1.1/Panic integration, not v1.0 unless explicitly promoted.

Risk: external app integration, user support burden.

## Work Package PR-9 - Dependency Watch Hardening

Objective: close the dependency-bot review item by validating existing
automation rather than creating duplicate automation.

Scope:

- `.github/workflows/nightly-upstream.yml`
- `scripts/ci/watch_upstream.py`
- `scripts/update_dependencies.sh`
- `docs/release/DEPENDENCY_POLICY.md`
- `docs/release/RELEASE_PIPELINE.md`

Non-goals:

- Do not auto-promote dependency updates.
- Do not write `requirements.txt` from automation.
- Do not open one issue per package unless the owner wants more issue noise.

Implementation:

- Keep the existing nightly schedule unless issue noise justifies changing it to
  weekly.
- Ensure the generated issue body explicitly calls out exact pinned packages,
  current version, candidate version, latest version, and required adoption gate.
- Add a small regression check if the workflow ever drifts from
  `watch_upstream.py`.

Acceptance:

- Manual dispatch produces `reports/upstream-watch.json`,
  `reports/upstream-watch.md`, and a tracking issue when drift exists.
- Candidate packages are informational only.
- Dependency promotion still requires candidate pins, audit, packaged import,
  offline smoke, corpus validation, license review, and rollback notes.

Validation:

```sh
scripts/update_dependencies.sh --check-only
```

Release gate: Nightly upstream validation and dependency audit.

Risk: upstream supply chain, CI noise.

## Work Package PR-10 - UI Spec Closure

Objective: decide which remaining design-spec ideas should actually ship and
stop carrying a spec/implementation gap as an open trust issue.

Scope:

- `docs/UI_DESIGN_SPEC.md`
- `docs/UI_IMPLEMENTATION_GATED_PLAN.md`
- `Upmarket/Upmarket/Views/ShelfView.swift`
- `Upmarket/Upmarket/Views/OnboardingView.swift`
- `Upmarket/Upmarket/Views/TourManager.swift`
- `Upmarket/UpmarketUITests/**`

Non-goals:

- Do not add cinematic onboarding ahead of history/CLI if the owner prioritizes
  workflow trust.
- Do not implement motion that is not tied to state or user action.
- Do not reintroduce paywall-at-tour-completion behavior.

Implementation:

- Mark already-shipped UI spec items as implemented in the gated plan.
- Decide whether progressive shelf card widths are still worth the layout risk.
- Decide whether corner snap ghost guides belong in v1.0 or v1.1.
- If implementing the 4-act onboarding, keep it product-level and do not expose
  internal converter package names.
- Add visual criteria before code changes.

Acceptance:

- UI spec status reflects reality.
- Any implemented motion has a state or workflow reason.
- Onboarding remains dismissible and never triggers paywall before conversion
  value.

Validation:

```sh
scripts/ci/gate.sh major
scripts/ci/validate_user_facing_copy.py
```

Manual validation:

- Light and dark screenshots across 13-inch laptop, wide desktop, and reduced
  motion/accessibility settings.

Release gate: UI automation and Gate E copy/privacy review.

Risk: polish consuming core reliability time, visual regressions.

## Suggested Sequence

| Sequence | Work | Estimated size | Why now |
| --- | --- | --- | --- |
| 1 | PR-1 UI trust pass | Small | Removes clipboard and stalled-job trust problems |
| 2 | PR-2 provenance badge | Small/medium | Makes conversion results legible and debuggable |
| 3 | PR-3 persistent history | Medium/large | Converts the app from transient utility to workflow tool |
| 4 | PR-4 structured output | Medium | Establishes output contract before CLI |
| 5 | PR-5 runtime progress | Medium/large | Fixes long AI conversion confidence |
| 6 | PR-6 CLI ADR and first CLI | Large | Unlocks developers, scripts, and LLM tool calls |
| 7 | PR-7 watch folders | Large | Background infrastructure after persistence is stable |
| 8 | PR-8 Nova extension | Small after CLI | Panic ecosystem story |
| 9 | PR-9 dependency watch hardening | Small | Keeps supply-chain automation honest |
| 10 | PR-10 UI spec closure | Variable | Craft polish once workflow trust is handled |

## Definition Of Done

Each package is done only when:

- implementation stays within its declared scope;
- release gate impact is recorded in `docs/IMPLEMENTATION_PLAN.md` if the item
  is promoted to P0 or v1.0;
- privacy implications are reviewed, especially for history and CLI output;
- user-facing copy avoids internal toolkit/package names;
- focused tests pass;
- the relevant local gate is run or the validation gap is stated in the handoff;
- manual UI/storage evidence is captured for UI, history, CLI, and watch-folder
  changes.
