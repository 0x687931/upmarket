# Vendored: SwiftOfficeMarkdown

Native, zero-dependency Office → Markdown engine. Vendored into Upmarket as a
local Swift package (same pattern as `Vendor/PythonKit`).

- **Upstream:** https://github.com/0x687931/SwiftOfficeMarkdown (private)
- **Version:** v0.9.0 (source commit `4fe65a5`)
- **License:** proprietary, © Andrew McArdle (see `LICENSE`)

## Why it's here

Replaces the Python (markitdown) path for Office formats so the **basic tier
converts `.docx/.xlsx/.pptx` and legacy `.doc/.xls/.xlsb/.ppt` natively** — no
CPython runtime required. Entry point: `OfficeToMarkdown.convert(fileURL:)`.

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
