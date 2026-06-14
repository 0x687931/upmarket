# Vendored: SwiftOfficeMarkdown

Native, zero-dependency Office → Markdown engine. Vendored into Upmarket as a
local Swift package (same pattern as `Vendor/PythonKit`).

- **Upstream:** https://github.com/0x687931/SwiftOfficeMarkdown (private)
- **Version:** v0.9.0 (source commit `4fe65a5`)
- **License:** proprietary, © Andrew McArdle (see `LICENSE`)

## Why it's here

A Python-free Office → Markdown engine. It removes Python from the **Basic
tier**: Word documents (`.docx`) are a Basic-tier format per the tier contract
(`AppTier.requiredTier(for:)`), so `ConversionRunner` converts them **natively
and in-process — no CPython runtime** — as the *primary* path at every tier
(the schema-driven engine is high fidelity, so there's no reason to prefer
Docling for `.docx`).

Spreadsheets/presentations (`.xlsx/.pptx`) stay **Pro** per the same contract:
they convert via the Enhanced (Docling) path with this engine as a Python-free
fallback if the runtime path fails. Entry point:
`OfficeToMarkdown.convert(fileURL:)`.

Routing lives in `ConversionRunner.extract()` (`.structuredDocument`) and the
tier floor in `ContentClassifier`.

Because Basic is native, the app **no longer embeds a Python runtime** — the
~104 MB `Python.framework` was removed from the Upmarket target's Frameworks/
Embed phases (release app ~21 MB vs ~125 MB before). Pro/Max download a
self-contained runtime via Background Assets. A re-embed guard in
`scripts/ci/verify_release_app.sh` fails the runtime gate if it comes back. For
local Pro testing, stage the source runtime with
`scripts/dev/stage_python_runtime.sh`.

## What was trimmed from upstream

To keep the app lean and avoid shipping non-runtime material, this vendored copy
includes **only the library target**. Excluded:

- `Tests/` and the `office2md` / `xsdgen` executables.
- `Reference/Schemas/` — ISO/IEC © XSDs used upstream only as a dev-time test
  oracle. **Not shipped.** (The `Package.swift` here is trimmed accordingly.)

## Updating

Re-copy `Sources/SwiftOfficeMarkdown/` from the upstream tag, bump the version
above, and re-run `gate.sh`. Do not edit the vendored source in place — fix
upstream and re-vendor.
