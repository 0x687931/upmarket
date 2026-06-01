# Release Pipeline

## Pipeline Goals

The release pipeline proves that Upmarket can be built, packaged, run offline, and submitted without surprise. It also catches upstream dependency drift before it reaches users.

This pipeline should stay small and explicit. Prefer shell scripts that can run locally and in CI over opaque services.

## Required Workflows

### PR CI

Runs on every pull request.

Checks:

- Xcode project path is valid.
- App builds with `Upmarket/Upmarket.xcodeproj`.
- Unit tests pass. PR CI intentionally skips UI automation because launch/UI tests change system appearance during automation.
- User-facing copy hides internal toolkit names outside licenses and explicit diagnostic previews.
- Effective `Info.plist` contains required keys.
- Entitlements match App Store policy.
- Python bundle imports first-party modules.
- Offline smoke conversion passes.
- No undeclared PATH tools are required for supported formats.

### Release Candidate CI

Runs manually or on `release/*` branches.

Checks:

- Clean archive build.
- Signed app entitlements inspection.
- Packaged app launch/import smoke.
- StoreKit configuration tests.
- UI automation tests, including launch and appearance coverage.
- Corpus smoke benchmark.
- Corpus benchmark output must meet `docs/release/corpus_baseline.json`; downgrades block release.
- Pathway benchmark output must meet `docs/release/corpus_pathway_baseline.json`; each corpus file is measured against every valid convert-to-Markdown pathway before release.
- Release-candidate CI uploads `corpus-pathway-comparison`, containing the Markdown comparison and JSON document-level results for owner review before shipping.
- Forensic benchmark inventory records exact benchmark package versions, binary versions, corpus source commits, benchmark-only model cache artifacts, and cache roots.
- Model missing/corrupt behavior.
- Diagnostic bundle generation.
- Privacy-sensitive logs are redacted.

`scripts/ci/verify_release_app.sh <Upmarket.app>` is the shared app-package gate for PR and release-candidate CI. It verifies the effective plist, entitlement policy, embedded runtime imports, runtime helper boundary, offline smoke conversion, and model-missing behavior against the built app bundle. Unsigned local/CI builds validate source entitlement policy; signed release verification must run with `UPMARKET_REQUIRE_SIGNED_ENTITLEMENTS=1` so missing embedded entitlements fail.

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
- record accuracy, average wall time, total wall time, failures, timeouts, and system load;
- separate CPU-only, OS-managed Apple acceleration, and explicit GPU-capable paths;
- treat large OCR/model paths as isolated work so a stall or native crash cannot block the app;
- only promote a concurrency change when it improves throughput without quality downgrade, UI responsiveness loss, memory pressure risk, or worse failure recovery.

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
scripts/ci/verify_xcode_project.sh
scripts/ci/verify_effective_plist.sh
scripts/ci/verify_entitlements.sh
scripts/ci/verify_python_bundle.sh
scripts/ci/smoke_convert_offline.sh
scripts/ci/validate_models.py
scripts/ci/validate_corpus.py
scripts/ci/validate_corpus_baseline.py
scripts/ci/validate_corpus_pathways.py
scripts/ci/summarize_corpus_pathway_reports.py
scripts/ci/validate_task_registry.py
scripts/ci/validate_p0_plan_sync.py
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
xcodebuild test -project Upmarket/Upmarket.xcodeproj -scheme Upmarket -destination 'platform=macOS' -only-testing:UpmarketTests CODE_SIGNING_ALLOWED=NO
```

Run UI automation only for release candidates or explicit UI changes, because those tests drive the app and may switch the system between light and dark appearance:

```sh
xcodebuild test -project Upmarket/Upmarket.xcodeproj -scheme Upmarket -destination 'platform=macOS' -only-testing:UpmarketUITests CODE_SIGNING_ALLOWED=NO
```
