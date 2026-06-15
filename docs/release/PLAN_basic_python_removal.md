# Plan: remove the bundled Basic-tier Python runtime

**Status: DONE** on `vendor-office-markdown`. The embed was removed in Xcode (Frameworks +
Sync Python Bridge phases), the release app is ~21 MB, and the supporting script/doc/test
work below has landed. Remaining: run `gate.sh runtime` on a machine with the Python build
toolchain (needs `build_python_env.sh`) to validate the reworked runtime gate end-to-end.

## What landed
- **Embed removed** (Xcode): `Python.xcframework` dropped from the Upmarket target's
  Frameworks + Embed phases; the "Sync Python Bridge" build phase deleted.
- **Re-embed guard:** `scripts/ci/verify_release_app.sh` now fails if the app contains
  `Contents/Frameworks/Python.framework`, and its runtime checks target the source xcframework.
- **Bridge sync+verify** restored as a `gate.sh runtime` step (`sync_and_verify_python_bridge.sh`).
- **Dev staging:** `scripts/dev/stage_python_runtime.sh` symlinks the source runtime into the
  helper's App Support path for local Pro testing (refuses to clobber a real download).
- **Tests:** packaged-runtime `PythonBridgeTests` skip (not fail) when no runtime is embedded.
- **Docs:** `Vendor/SwiftOfficeMarkdown/UPMARKET_VENDOR.md` updated.

---

_Original plan (for reference):_

## Why

The Basic tier is now fully native (no Python): DOCX/DOC via `SwiftOfficeMarkdown`,
TXT/MD/CSV via `NativeTextConverter`, HTML via `NativeHTMLConverter`, PDF via PDFKit,
images via ImageIO/Vision. Tier gating enforces it — `ContentClassifier` classifies every
Basic document/text format to the `.native` capability, guarded by
`ContentClassifierTests.testBasicDocumentFormatsRequireNoRuntime`.

But the app still **embeds a ~104 MB `Python.framework`** carrying the Basic-tier packages
(`requirements-basic.txt`: `markitdown, mammoth, lxml, pypdfium2, Pillow, numpy, pydantic`)
— every one now replaced natively. Removing it drops the app from ~157 MB to ~53 MB and
makes "Basic ships no Python" literally true.

## Current state (verified)

- **Embed phase:** the **Upmarket app target** has an `Embed Frameworks` build phase that
  copies `Python.xcframework` (`project.pbxproj`: build file `81E090C2…`, phase
  `81E090C3…`, on target `Upmarket`). It is also listed in the target's `Frameworks` phase.
  No `-lpython`/weak-link flags → PythonKit `dlopen`s at runtime, so removing the embed does
  not break link-time.
- **Helper runtime resolution** (`UpmarketRuntimeHelper/main.swift:322` `resolveFrameworkRoot()`):
  1. **Primary:** downloaded `~/Library/Application Support/Upmarket/runtime/python_runtime/Python.framework/Versions/3.12`.
  2. Fallbacks (commented *"development builds / CI only"*): sibling `Python.framework`, then
     `Upmarket.app/Contents/Frameworks/Python.framework`, then `../Frameworks/Python.framework`.
- **Pro/Max runtime is a self-contained download:** `FirstPartyModelDownloadService.swift:481`
  expects the `pythonRuntime` asset to contain its own `Python.framework`. `ModelAsset.pythonRuntime`
  is `.backgroundAssets`, `requiredTier == .pro`. So Pro/Max do **not** depend on the bundled framework.
- **CI bundle check** (`scripts/ci/verify_python_bundle.sh`) inspects the **source** xcframework
  (`Upmarket/Python/Python.xcframework/.../site-packages`), not the copy inside `Upmarket.app`,
  so it is unaffected by dropping the embed.

Conclusion: the bundled framework is already architecturally "dev/CI only." Production correctness
does not depend on it once Basic is native.

## Change set (ordered; owner in brackets)

1. **[Xcode — do NOT hand-edit pbxproj]** Remove `Python.xcframework` from the Upmarket app
   target's **Embed Frameworks** phase (and from its **Frameworks** link phase if present).
   Keep the file reference and the source xcframework in the repo for CI/dev + building the
   Pro download. *Rationale for Xcode-not-hand-edit: project rule; pbxproj IDs and phase
   membership are easy to corrupt by hand.*
2. **[Xcode]** Review the **"Sync Python Bridge"** build phase. It currently copies
   `docling_bridge`/`upmarket_models` into the bundle's framework site-packages
   (`project.pbxproj:567+`). If the framework is no longer embedded, this phase has no target
   dir in the app → either remove it from the app target or repoint it at the Pro-download
   staging used by `stage_*_model_assets.py`. Confirm the Pro download still receives the bridge.
3. **[Claude]** Dev/CI helper fallback: with no embedded framework, the helper's fallback paths
   (main.swift:331–348) won't resolve during local Pro conversions unless the download exists.
   Add a fallback to the **source** xcframework (`Upmarket/Python/Python.xcframework/macos-arm64_x86_64/
   Python.framework/Versions/3.12`) for dev/CI, or have `scripts/dev/run_app.sh` stage it into
   Application Support. Pick whichever keeps PythonBridgeTests green without the embed.
4. **[Claude]** `scripts/ci/gate.sh runtime` + `verify_release_app.sh`: add an assertion that the
   **release** `Upmarket.app` does **not** contain `Contents/Frameworks/Python.framework`
   (positive guard against re-embedding). Keep `verify_python_bundle.sh` pointed at the source
   xcframework.
5. **[Claude]** Docs: update `docs/TIER_CONTRACT.md` pointer and
   `Vendor/SwiftOfficeMarkdown/UPMARKET_VENDOR.md` to state Basic ships no Python; note the app
   no longer embeds a runtime. Re-run `scripts/docs/generate_repo_docs.py`.

## Risks

- **PythonBridgeTests / runtime gate** likely rely on the bundled framework today. Step 3 must
  land first or they break. Verify how those tests currently obtain Python (source xcframework
  vs bundled copy) before removing the embed.
- **Signing / notarization:** fewer embedded frameworks is simpler, but re-confirm the
  `verify_release_app.sh` codesign walk still passes (no dangling references to the removed
  framework in any phase).
- **Background Assets delivery for Pro** must be exercised end-to-end (download → resolve →
  convert) on a clean profile, since Basic no longer provides a "warm" interpreter.

## Validation checklist (before merge)

- [ ] `scripts/ci/gate.sh quick` green.
- [ ] `scripts/ci/gate.sh runtime` green (includes new no-embed assertion).
- [ ] Release `Upmarket.app` has **no** `Contents/Frameworks/Python.framework`; size ≈ 53 MB.
- [ ] Basic conversions (docx/doc/txt/md/csv/html/pdf/image) succeed offline with the runtime
      asset **absent**.
- [ ] Pro path: download `pythonRuntime`, then a `.xlsx`/`.pptx`/`.epub` conversion succeeds;
      helper resolves the **downloaded** framework.
- [ ] PythonBridgeTests green via the dev/CI source-xcframework fallback.
