# Vendored: SwiftOfficeMarkdown

Native, zero-dependency Office → Markdown engine. Vendored into Upmarket as a
local Swift package (same pattern as `Vendor/PythonKit`).

- **Upstream:** https://github.com/0x687931/SwiftOfficeMarkdown (private)
- **Version:** v0.9.0 (source commit `4fe65a5`)
- **License:** proprietary, © Andrew McArdle (see `LICENSE`)

## Why it's here

A Python-free Office → Markdown engine used **inside the Enhanced (Pro) path**
as a fallback: when the Docling/MarkItDown runtime path fails (e.g. a helper
crash), `ConversionRunner` falls back to this engine so the user still gets
Markdown for `.docx/.xlsx/.pptx` and legacy `.doc/.xls/.xlsb/.ppt`. It does
**not** change tier gating — the tier contract (`AppTier.requiredTier(for:)`)
still gates Office formats above Basic. Entry point:
`OfficeToMarkdown.convert(fileURL:)`.

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
