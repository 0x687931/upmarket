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
