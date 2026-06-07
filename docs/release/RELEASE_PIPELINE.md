# Release Pipeline

## Pipeline Goals

The release pipeline proves that Upmarket can be built, packaged, run offline, and submitted without surprise. It also catches upstream dependency drift before it reaches users.

This pipeline should stay small and explicit. Prefer shell scripts that can run locally and in CI over opaque services.

## Required Workflows

Release control documents:

- `docs/release/RELEASE_POLICY.md`
- `docs/release/RELEASE_CHECKLIST.md`
- `docs/release/TEST_MATRIX.md`

### PR CI

Runs on every pull request with `scripts/ci/gate.sh quick`.

Checks:

- GitHub Actions uses `macos-26` with `DEVELOPER_DIR=/Applications/Xcode_26.5.app/Contents/Developer`, matching the project format written by local Xcode 26.5.
- Cached generated Python runtime is present as a build input; CI runs `scripts/ci/ensure_python_runtime.sh` to rebuild it only when missing or stale.
- Xcode 26 or newer is selected and the project path is valid.
- Architecture simplification holds: no hidden launch windows, zero-size placeholder scenes, or create-then-hide AppKit window workarounds.
- Philosophy remediation regression guards pass.
- User-facing copy hides internal toolkit names outside licenses and explicit diagnostic previews.
- Entitlements match App Store policy.
- Generated repository documentation is current.
- App builds unsigned with `Upmarket/Upmarket.xcodeproj`.
- Effective `Info.plist` contains required keys.
- Unit tests pass.
- No undeclared PATH tools are required for supported formats.

PR CI intentionally skips UI automation, release-level runtime rebuilding, packaged-app smoke, and corpus/model baselines. The ignored runtime framework is still prepared because the Xcode target needs it to compile. Run `scripts/ci/gate.sh runtime` for Python, dependency, entitlement, model, corpus, or packaging changes, then broaden to the release-candidate gate before shipping.

### UI Automation CI

Runs automatically through `.github/workflows/ui-automation.yml` when a pull request or main-branch push touches UI-sensitive files, the Xcode project, `UpmarketUITests`, or the UI gate script. It also supports manual dispatch.

Checks:

- Xcode 26.5 is selected.
- Cached generated Python runtime is prepared so the app target can build.
- `scripts/ci/gate.sh ui` runs Apple XCTest UI automation against `UpmarketUITests`.
- The generated `.xcresult` bundle under `build/TestResults/` is uploaded for triage.

This workflow is the automatic UI lane. Release candidates still run UI automation again through `.github/workflows/release-candidate.yml`.

### Release Candidate CI

Runs manually or on `release/*` branches with `scripts/ci/gate.sh release` before archive and benchmark steps.

Checks:

- GitHub Actions uses `macos-26` with Xcode 26.5 selected through `DEVELOPER_DIR`.
- Clean runtime rebuild from release pins.
- Clean archive build.
- Source entitlement policy; signed app entitlements inspection when a signing identity is available.
- Packaged app launch/import smoke.
- StoreKit configuration tests.
- UI automation tests, including launch and appearance coverage.
- Corpus smoke benchmark.
- Corpus benchmark output must meet `docs/release/corpus_baseline.json`; downgrades block release.
- Pathway benchmark output must meet `docs/release/corpus_pathway_baseline.json`; each corpus file is measured against every valid convert-to-Markdown pathway before release.
- Release-candidate CI uploads `corpus-pathway-comparison`, containing the Markdown comparison and JSON document-level results for owner review before shipping.
- Forensic benchmark inventory records exact benchmark package versions, binary versions, corpus source commits, benchmark-only model cache artifacts, and cache roots.
- Model missing/corrupt behavior.
- Python bridge security preflight for unsafe archives, mismatched file signatures, pathological image/PDF inputs, subprocess launch, and conversion-time network blocking.
- Diagnostic bundle generation.
- Privacy-sensitive logs are redacted.

`scripts/ci/verify_release_app.sh <Upmarket.app>` is the shared app-package gate for runtime and release-candidate CI. It verifies the effective plist, entitlement policy, Apple Foundation bundle preflight for the embedded runtime framework, embedded runtime imports, Python bridge security preflight, runtime helper boundary, offline smoke conversion, and model-missing behavior against the built app bundle. Unsigned local/CI builds validate source entitlement policy; signed release verification must run with `UPMARKET_REQUIRE_SIGNED_ENTITLEMENTS=1` so missing embedded entitlements fail.

Swift Testing is allowed for new pure Swift unit and integration tests in `UpmarketTests`, and XCTest remains required for UI automation and performance tests. Both frameworks may coexist in the test bundle, but do not mix their APIs inside one test file.

Detailed UI automation policy lives in `docs/release/UI_AUTOMATION.md`.

Python tests are required for Python bridge, runtime, dependency, model, and packaging changes, but they should stay boundary-focused. Use script gates that run against the bundled Python 3.12 `site-packages`, such as `scripts/ci/test_archive_security.py`, `scripts/ci/test_model_faults.py`, `scripts/ci/verify_python_bundle.sh`, and `scripts/ci/smoke_convert_offline.sh`. Do not make the vendored upstream Docling pytest suite part of normal Upmarket CI unless a scoped corpus/upstream task calls for it.

### TestFlight Beta Lane

TestFlight starts only after the release-candidate gate, signed archive, and package verification pass. It is for validating distribution, feedback, crash diagnostics, sandbox purchases, and real-user workflow confidence; it is not a replacement for local gates.

Internal beta:

- Upload a signed archive to App Store Connect with normal App Store/TestFlight eligibility, not an internal-only build unless the build will never go external.
- Assign the build to an internal TestFlight group first.
- Record build number, commit SHA, archive path, tester group, and 90-day expiry date in the release issue.
- Review TestFlight feedback, sessions/crashes, Xcode Organizer crash diagnostics, StoreKit sandbox behavior, and diagnostic bundle quality before widening.

External beta:

- Complete TestFlight test information: beta app description, What to Test, feedback email, support contact, and review notes.
- Submit for TestFlight App Review when required.
- Use a small external group or constrained public link first.
- Do not widen distribution until external feedback has an owner decision: fix now, document known issue, or reject the candidate.

### Nightly Upstream Validation

Runs on a schedule.

Checks current and candidate upstream sources:

- BeeWare Python Apple support
- Docling
- MarkItDown
- pypdfium2
- Hugging Face Hub
- Transformers
- Torch / MLX
- Xcode/macOS SDK changes

Nightly should report changes, not auto-promote them. The GitHub Action runs `scripts/ci/watch_upstream.py`, uploads `reports/upstream-watch.json` and `reports/upstream-watch.md`, and creates or updates one tracking issue when candidates or blocked checks exist.
It also prepares the ignored Python runtime through the same cached `scripts/ci/ensure_python_runtime.sh` path before validating bundled imports, so a clean checkout can run the workflow.

Run the same check locally before dependency work:

```sh
scripts/ci/watch_upstream.py
```

### Dependency Audit

Runs weekly and when Python dependencies change.

Checks:

- exact pinned versions;
- current/candidate lock consistency;
- `pip check`;
- license generation;
- vulnerability review where practical;
- no undeclared runtime binary dependency such as `ffprobe` or `exiftool`.

The audit workflow pins Python 3.12 before creating its virtualenv so dependency checks match the bundled runtime version.

The dependency policy is `docs/release/DEPENDENCY_POLICY.md`. `requirements.txt` is the release-current state; `requirements-candidate.txt` is the only place proposed Python runtime updates may be staged before validation.

## Dependency States

Use three states:

- `current`: exact pins in `requirements.txt`, used for release.
- `candidate`: exact pins in `requirements-candidate.txt`, under validation.
- `latest-upstream`: exploratory nightly check only, reported by upstream watch.

Promotion rule:

```text
latest-upstream -> candidate -> current
```

No dependency moves to `current` without corpus smoke, packaged import, offline conversion validation, license review, rollback notes, and human review.

## Benchmark Optimisation Loop

Do not change conversion queue concurrency from intuition. Use the corpus/pathway benchmark matrix to compare serial and parallel execution separately from converter quality:

- run the same corpus, pathway, dependency versions, and model cache;
- record accuracy, average wall time, total wall time, expected blocked states, failures, timeouts, and system load;
- separate CPU-only, OS-managed Apple acceleration, and explicit GPU-capable paths;
- treat large OCR/model paths as isolated work so a stall or native crash cannot block the app;
- only promote a concurrency change when it improves throughput without quality downgrade, UI responsiveness loss, memory pressure risk, or worse failure recovery.

Run the local comparison with:

```sh
scripts/benchmark_concurrency.py --pathway python-fast-pdfium --workers 4 --json-output reports/concurrency-python-fast-pdfium.json --markdown-output reports/concurrency-python-fast-pdfium.md
```

Committed release evidence lives in `docs/release/SERIAL_PARALLEL_BENCHMARKS.md`; ignored raw JSON/Markdown outputs remain under `reports/` for local inspection.

## Upstream Issue and Patch Intake

Upstream work must enter Upmarket through a controlled intake path. Do not copy patches, bump packages, or change runtime behavior just because an upstream issue looks relevant.

Track upstream inputs as one of:

- `upstream-watch`: relevant issue, no action yet.
- `upstream-candidate`: fix or release exists and is worth validating.
- `upstream-adopted`: validated and merged into Upmarket.
- `upstream-rejected`: not relevant, too risky, or replaced by local mitigation.
- `upstream-blocked`: waiting on upstream release, clarification, or license/security review.
- `upstream-fork`: temporary Upmarket fork/cherry-pick under validation.

Required intake fields:

- upstream project and issue/PR/release URL;
- affected Upmarket feature or pipeline;
- expected user impact;
- affected dependency version or model revision;
- fork URL, base version, branch, commit SHA, and checksum when a fork/cherry-pick is involved;
- local reproduction case or corpus document;
- security/privacy/App Store impact;
- rollback plan.

Adoption workflow:

```text
upstream-watch
  -> reproduce locally or identify matching corpus case
  -> create candidate dependency/model/source patch
  -> run dependency audit
  -> run packaged import/offline smoke
  -> run relevant corpus benchmark
  -> compare output and performance against current
  -> add an ADR for any local upstream patch
  -> pin fork/cherry-pick candidates to immutable commits or packaged artifacts
  -> promote to current or reject
```

If the upstream change touches conversion quality, add or update a corpus fixture before adopting it. If it touches Python packaging, model loading, entitlements, sandbox behavior, or network behavior, treat it as P0 until proven otherwise.

Local patches to upstream code are allowed only when:

- the patch is small and isolated;
- the upstream issue/PR is linked;
- any fork branch is pinned to an immutable commit before release;
- the patch is documented in an ADR;
- a removal condition is defined;
- CI proves the patch is present in the packaged app.

## Local Hook Scripts

Target scripts:

```text
scripts/ci/gate.sh
scripts/ci/ensure_python_runtime.sh
scripts/ci/verify_xcode_project.sh
scripts/ci/verify_effective_plist.sh
scripts/ci/verify_entitlements.sh
scripts/ci/verify_python_bundle.sh
scripts/ci/test_archive_security.py
scripts/ci/smoke_convert_offline.sh
scripts/ci/validate_models.py
scripts/ci/test_model_faults.py
scripts/ci/validate_corpus.py
scripts/ci/validate_corpus_baseline.py
scripts/ci/validate_corpus_expected_status.py
scripts/ci/validate_corpus_pathways.py
scripts/ci/summarize_corpus_pathway_reports.py
scripts/ci/validate_task_registry.py
scripts/ci/validate_p0_plan_sync.py
scripts/ci/validate_release_regression_guards.py
scripts/ci/validate_architecture_boundaries.py
scripts/ci/validate_user_facing_copy.py
scripts/ci/validate_runtime_helper.py
```

Each script must:

- run locally;
- exit nonzero on failure;
- print a short actionable failure message;
- avoid network unless the script name says it validates upstream/download behavior.

## Release Gate Mapping

- Gate A: build, archive, plist, entitlements, runtime helper, Python bundle.
- Gate B: corpus, offline conversion, model states, temp cleanup.
- Gate C: OSLog, diagnostics, liveness, fault injection, memory pressure.
- Gate D: StoreKit, App Store Connect, signing, products.
- Gate E: legal, privacy, support, screenshots, listing.

## Human Review Points

Human review is required for:

- App Store Connect product setup.
- App Privacy answers.
- Legal/privacy policy changes.
- Screenshots and listing copy.
- Promoting dependency candidates to current.
- Removing any P0 task from v1.0 scope.

## Local Test Policy

Use unit tests during normal P0 implementation:

```sh
scripts/ci/gate.sh quick
```

Use the runtime gate for Python, dependency, entitlement, model, corpus, or packaging changes:

```sh
scripts/ci/gate.sh runtime
```

If a local quick build reports that `Upmarket/Python/Python.xcframework` is missing, prepare the ignored build artifact first:

```sh
scripts/ci/ensure_python_runtime.sh
```

Run UI automation only through `scripts/ci/gate.sh major` or `scripts/ci/gate.sh ui` for release candidates or explicit UI changes, because those tests drive the app and may switch the system between light and dark appearance.
