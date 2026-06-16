# App Size — native-only is a huge win

Removing the embedded CPython + Docling runtime and converting natively in Swift
collapsed Upmarket's footprint. The whole product — every conversion engine plus
on-device AI — now ships in a **~25 MB app** with a **~7.6 MB download**, and the
**Pro tier needs no download at all**.

## Shipping app (Release archive, Apple Silicon)

Measured from `xcodebuild archive` (Release, stripped — the actual shippable binary;
symbols go to a separate dSYM, not the download), then re-signed locally with the
**Apple Distribution** cert (`Q54Q5726NT`) to confirm signed size:

| Metric | Size |
| --- | --- |
| **Install size** (uncompressed signed `Upmarket.app`) | **~25 MB** |
| **Download** (compressed signed package) | **~7.5 MB** |
| Main binary `Upmarket` (stripped) | 20 MB — dominated by statically-linked mlx-swift (Granite inference) |
| `upmarket-cli` / `upmarket-mcp` | 270 KB / 122 KB |
| Embedded `Python.framework` | **none** |
| dSYMs (uploaded for crash symbolication, **not** downloaded) | ~231 MB |

> A plain `xcodebuild build -configuration Release` reports ~73 MB because it does not
> strip symbols; the archive (which is what ships) strips them into the dSYM. The exact
> App Store download/install figures come from App Store Connect after upload — the
> numbers above are the local archive measurement.

## Before vs after

| | Before (Python runtime) | Now (native Swift) |
| --- | --- | --- |
| App download | lean Swift app | **~7.6 MB** (all engines + mlx-swift Granite in-app) |
| **Pro tier** post-purchase download | **~1.3 GB** embedded Python runtime (Docling, MarkItDown, pdfium, torch, transformers, …) | **0 — fully native, nothing to download** |
| **Max tier** post-purchase download | ~1.3 GB runtime **+** model weights | **~600 MB Granite model only** |
| First-run footprint, Max user | ~1.9 GB+ | **~625 MB** |
| Separate helper process | `UpmarketRuntimeHelper` (per-job CPython host) | none — conversion is in-process |

## Why it shrank

- The **~1.3 GB Python runtime is gone entirely.** Office/HTML/text/EPUB convert with
  native Swift engines (SwiftOfficeMarkdown, libxml2, ZipReader); PDFs use PDFKit + Vision.
- **Granite-Docling moved from a Python MLX download into the app** as statically-linked
  mlx-swift — that adds ~20 MB to the binary but removes the multi-hundred-MB Python ML stack
  and lets Pro ship with **zero** downloads.
- No `Python.xcframework`, no `PythonKit`, no per-job helper process.

The only gated download left is the **Max-tier Granite model** (~600 MB), and even that is
optional — Basic and Pro are fully functional offline the moment the app is installed.
