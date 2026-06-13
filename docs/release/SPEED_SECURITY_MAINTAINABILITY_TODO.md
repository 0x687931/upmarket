# Speed, Security, and Maintainability TODO

Initial review date: 2026-06-13

This is a staging document for follow-up engineering work. Each item needs a
GitHub issue or agent checklist before implementation. Keep fixes narrow,
preserve the single conversion entry point, and run the listed gate before
handoff.

## TODO-001: Bound Native PDFKit Extraction

Status: implemented on 2026-06-13.

Implementation notes:
- `PDFConverter` enforces explicit PDFKit page and page-geometry limits through
  `VisionProcessingLimits`.
- PDFKit output assembly no longer retains a separate `[String]` of every page.
- `PDFConverterTests` covers small digital PDFs, over-limit page count, and
  extreme page geometry.

Objective: prevent the native digital-PDF path from processing arbitrarily large
or pathological PDFs after the source file passes the 500 MB workspace-copy
limit.

Scope:
- `Upmarket/Upmarket/Services/PDFConverter.swift`
- `Upmarket/Upmarket/Services/VisionProcessingLimits.swift`
- focused tests in `Upmarket/UpmarketTests/`

Problem evidence:
- `PDFConverter.convert(url:password:)` opens a `PDFDocument`, reads
  `pageCount`, loops every page, collects page Markdown in `[String]`, and joins
  the full output at the end.
- Vision and Python paths already enforce page, image, PDF, and archive safety
  limits. The PDFKit path should not be the unbounded exception.

Non-goals:
- Do not rewrite PDF extraction quality heuristics.
- Do not add a new PDF engine.
- Do not change pricing or tier routing.

Acceptance criteria:
- Native PDFKit conversion rejects PDFs above an explicit page-count limit with
  product-level error copy.
- Native PDFKit conversion rejects invalid or extreme page geometry before
  rendering or extracting every page.
- Large-output assembly avoids retaining unnecessary per-page temporary strings.
- Tests cover an over-limit page count, invalid page dimensions if fixture
  creation is practical, and a normal small digital PDF.

Release gate: `scripts/ci/gate.sh quick`. Run corpus PDF benchmarks if extraction
behavior changes.

Risk area: speed, memory pressure, untrusted document handling.

## TODO-002: Stop Passing Full Conversion Output Through JSON IPC

Status: implemented on 2026-06-13 for helper stdout JSON, app/CLI handoff JSON,
and MCP file-mode reads.

Implementation notes:
- `UpmarketRuntimeHelper` writes conversion Markdown to the job workspace and
  returns `markdownFile`; `RuntimeHelperClient` validates the returned path is
  inside the workspace before reading it.
- CLI handoff responses return `outputFile` metadata and store formatted output
  beside `response.json`.
- MCP file mode and oversized responses return file references without reading
  full converted output into memory.

Objective: move large Markdown payloads across helper, CLI, and MCP boundaries by
file reference instead of embedding complete document output in JSON responses.

Scope:
- `Upmarket/UpmarketRuntimeHelper/main.swift`
- `Upmarket/Upmarket/Services/RuntimeHelperClient.swift`
- `Upmarket/Upmarket/Services/CLIConversionBroker.swift`
- `Upmarket/UpmarketCLI/UpmarketCLI.swift`
- `Upmarket/UpmarketMCP/UpmarketCLIRunner.swift`
- DTO tests in `Upmarket/UpmarketTests/` and MCP/CLI tests where present

Problem evidence:
- The runtime helper emits `RuntimeConversionOutputDTO.markdown` as a full JSON
  string over stdout.
- `RuntimeHelperClient` buffers helper output lines in memory.
- CLI handoff writes full output into `response.json`.
- MCP reads the full output file into a `String` even when it will return a file
  path for large results.

Non-goals:
- Do not add XPC or a daemon.
- Do not expose raw user-selected source paths.
- Do not remove the existing inline-return mode for small MCP responses.

Acceptance criteria:
- Helper conversion can write Markdown to an app-owned workspace output file and
  return only path, byte count, page count, format, title, pipeline, and selected
  pathway.
- The app validates that returned output paths are inside the job workspace
  before reading or copying.
- CLI handoff response carries an output file reference for large output, with a
  documented inline cap for small output.
- MCP file mode does not read the full converted document into memory.
- Tests cover small inline output, large file-reference output, invalid returned
  paths, and cleanup on failure/cancellation.

Release gate: `scripts/ci/gate.sh quick`; use `scripts/ci/gate.sh runtime` if the
packaged helper contract or app bundle verification changes.

Risk area: speed, memory pressure, privacy, process-boundary safety.

## TODO-003: Budget Multi-Path PDF Candidate Execution

Status: implemented on 2026-06-13 with a first-pass explicit page/quality budget.

Implementation notes:
- `PDFCandidateBudget` bounds full PDFKit+Vision+AI fan-out by page count.
- Strong PDFKit output can skip secondary candidates.
- Secondary candidates are rejected beyond the Vision page budget.
- `PDFCandidateBudgetTests` documents the budget thresholds.

Objective: avoid running PDFKit, Vision OCR, and AI conversion concurrently for a
single scanned PDF when the expected memory and compute cost is too high.

Scope:
- `Upmarket/Upmarket/Services/ConversionRunner.swift`
- `Upmarket/Upmarket/Services/MarkdownQualityScorer.swift`
- `Upmarket/Upmarket/Services/NativeDocumentClassifier.swift`
- benchmark documentation under `docs/release/`

Problem evidence:
- `runQualitySelectedPDFConversion(... secondary: .all)` starts PDFKit, Vision,
  and Python/AI candidates concurrently.
- This can parse/render the same document multiple times and load a separate ML
  runtime while Vision is rendering pages.

Non-goals:
- Do not make the queue globally parallel.
- Do not remove quality selection.
- Do not lower output quality to win a synthetic benchmark.

Acceptance criteria:
- Candidate execution has an explicit budget based on file size, page count,
  classifier evidence, current memory pressure, and AI availability.
- Cheap/native candidates run first when they are likely sufficient.
- Expensive candidates are skipped or deferred when budget says the user-visible
  risk is too high.
- If concurrent candidates remain for small/high-value cases, loser tasks are
  cancelled once no longer useful.
- Benchmarks record wall time, peak memory where practical, and output quality
  for representative scanned, digital, and complex PDFs.

Release gate: `scripts/ci/gate.sh quick` plus the conversion/concurrency
benchmark path documented in `docs/release/TEST_MATRIX.md`.

Risk area: speed, memory pressure, conversion quality.

## TODO-004: Add MCP-Side Conversion Timeout

Status: implemented on 2026-06-13.

Implementation notes:
- `UpmarketCLIRunner` has an MCP-local timeout, graceful termination, forced
  kill fallback, and partial-output cleanup.
- `validate_mcp_server.py` covers success, nonzero CLI exit, timeout, and
  partial-output removal.

Objective: prevent one MCP request from blocking on a child `upmarket-cli`
process for the CLI's full response timeout.

Scope:
- `Upmarket/UpmarketMCP/UpmarketCLIRunner.swift`
- `Upmarket/UpmarketMCP/` tests
- `docs/release/MCP_LM_STUDIO_IMPLEMENTATION_PLAN.md` if behavior changes

Problem evidence:
- `UpmarketCLIRunner.runCLI(arguments:)` calls `process.waitUntilExit()` without
  a local timeout.
- `upmarket-cli` can wait up to two hours for an app conversion response.

Non-goals:
- Do not change the app-side conversion timeout for normal CLI use unless a
  separate issue proves it is wrong.
- Do not add an HTTP server, background listener, or second conversion path.

Acceptance criteria:
- MCP has an explicit timeout shorter than the CLI response timeout.
- On timeout, MCP terminates the child process, removes the partial output file,
  and returns a product-level tool error.
- Tests cover successful conversion, nonzero CLI exit, and timeout cleanup.

Release gate: `scripts/ci/gate.sh quick`; use runtime/package validation if MCP
bundle verification changes.

Risk area: availability, resource cleanup, tool integration safety.

## TODO-005: Split ConversionRunner by Real Policy Boundaries

Status: implemented on 2026-06-13.

Implementation notes:
- PDF candidate policy moved to `PDFCandidateBudget`.
- Output post-processing moved to `ConversionPostProcessor`.
- Media fallback remains in `ConversionRunner` because it is part of the
  immediate extraction route and has existing pathway coverage.

Objective: reduce conversion-routing risk without introducing speculative
architecture.

Scope:
- `Upmarket/Upmarket/Services/ConversionRunner.swift`
- new small service files only if they map to existing concrete behavior
- existing `ConversionQueueTests` and pathway tests

Problem evidence:
- `ConversionRunner` owns workspace copy, capability gates, content routing,
  candidate execution, audio fallback, Python fallback, quality selection, and
  post-processing in one file.
- This makes speed/security fixes harder because unrelated policies live in the
  same edit surface.

Non-goals:
- Do not add protocols for future engines.
- Do not change `ConversionQueue.add()` -> `ConversionRunner.run()` as the
  single app entry point.
- Do not move business logic into SwiftUI views.

Acceptance criteria:
- Capability gating, PDF candidate execution, media fallback, and post-processing
  are separable units with direct tests or preserved existing coverage.
- Public behavior and diagnostics remain stable unless a linked TODO requires a
  deliberate change.
- File ownership is clear enough for future agents to edit one area narrowly.

Release gate: `scripts/ci/gate.sh quick`.

Risk area: maintainability, regression containment.

## TODO-006: Split NativeDocumentClassifier Into Cheap and Expensive Phases

Status: implemented on 2026-06-13.

Implementation notes:
- `NativeDocumentClassifier.classify` now has an explicit PDFKit cheap
  inspection phase followed by Vision inspection and evidence merge.
- The Vision helpers remain in the same file to avoid a broad private-symbol
  move; the runtime cost boundary is now explicit at the call site.

Objective: make document classification cost explicit and avoid doing Vision
render inspection when cheap PDF/text evidence is enough.

Scope:
- `Upmarket/Upmarket/Services/NativeDocumentClassifier.swift`
- `Upmarket/Upmarket/Services/VisionProcessingLimits.swift`
- classifier tests and benchmark docs

Problem evidence:
- The classifier file mixes evidence DTOs, PDF sampling, page preflight,
  language detection, Vision rendering, Vision text/layout inspection, and final
  routing policy.
- Expensive inspection is easier to trigger accidentally because cheap and
  expensive paths are not visibly separated.

Non-goals:
- Do not remove Vision inspection.
- Do not weaken scanned-document detection without benchmark evidence.

Acceptance criteria:
- Cheap classification can inspect PDF text/page metadata without rendering.
- Expensive Vision inspection is a separate phase with an explicit budget or
  reason.
- Tests cover cheap-only classification, expensive-inspection escalation, and
  unavailable Vision/Core ML behavior.

Release gate: `scripts/ci/gate.sh quick`; run corpus pathway benchmarks if
recommendation behavior changes.

Risk area: speed, maintainability, routing correctness.

## TODO-007: Make Python Dependency Tiers Auditable

Status: implemented on 2026-06-13.

Implementation notes:
- `validate_dependency_lock.py` now validates current, candidate, Basic, Pro,
  and AI lock files together.
- Release-current must equal the Basic+Pro+AI union.
- Basic is constrained to the small native/OCR utility set, and Pro rejects
  AI-only frameworks.
- `DEPENDENCY_POLICY.md` documents the tier invariant.

Objective: ensure the dependency lock shape matches the intended lean app plus
post-purchase runtime/model download strategy.

Scope:
- `requirements.txt`
- `requirements-candidate.txt`
- runtime build scripts under `scripts/`
- dependency/release docs under `docs/release/`

Problem evidence:
- The release-current dependency file lists fast conversion, enhanced conversion,
  Torch, Transformers, MLX, MLX-VLM, OCR, Pillow, and NumPy together.
- If packaging scripts split these into tiered artifacts, the split should be
  visible and validated. If they do not, the lock file is hiding package bloat.

Non-goals:
- Do not update dependency versions in this task.
- Do not remove a dependency without corpus and packaged-runtime evidence.

Acceptance criteria:
- The runtime build path clearly documents which dependencies ship with the base
  runtime and which belong to Pro/AI downloads.
- CI or release validation fails if an AI-only dependency is accidentally pulled
  into the base runtime.
- License and vulnerability review still operate on the effective packaged
  dependency sets.

Release gate: `scripts/ci/gate.sh runtime` plus dependency validation scripts.

Risk area: package size, supply chain, App Store review, maintainability.
