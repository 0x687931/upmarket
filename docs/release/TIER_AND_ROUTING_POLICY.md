# Tier and Routing Policy

Upmarket has two product tiers. It may use multiple conversion engines inside those tiers, but those engines are implementation details and must not become separate user-facing products.

## Product Tiers

| Tier | Promise | Included paths |
| --- | --- | --- |
| Basic | Fast private conversion for standard files. | Apple-native conversion, metadata extraction, and bundled fast digital conversion. |
| Enhanced | Advanced local conversion for complex layouts, scanned documents, and visual documents when this Mac can safely run the required model. | Docling IBM models, Granite Docling MLX, and Granite Vision 4.1 4B, gated by hardware, disk, memory, and model download state. |

Enhanced is one product tier, not three separate tiers. The app may show that some Enhanced capabilities are unavailable on a specific Mac, but it should not expose implementation package names in normal user-facing copy.

## Basic Routing

Basic should prefer Apple-native APIs and small local conversion paths.

| Input need | Preferred path | Role |
| --- | --- | --- |
| Digital PDF text | PDFKit | Fast text extraction and simple Markdown cleanup. |
| Image or scanned PDF text | Apple Vision OCR | Private on-device OCR baseline. |
| Image metadata | ImageIO | Dimensions, color profile, EXIF where available. |
| Audio/video metadata | AVFoundation | Local media metadata. |
| Audio speech where available | Apple Speech | Native transcription, subject to system authorization and recognizer availability. |
| DOCX, PPTX, XLSX, HTML, CSV, JSON, XML, EPUB, ZIP | MarkItDown | Fast conversion for digital structured files. |

MarkItDown image support is not a substitute for chart or document visual understanding in Upmarket. In the current local runtime it returns image metadata for chart images unless an OCR/LLM backend is configured. Cloud-backed OCR or LLM backends are not part of runtime conversion.

ZIP and ZIP-based formats must be treated as hostile input. Basic may only pass ZIP, DOCX, PPTX, XLSX, or EPUB files to converters after archive preflight rejects zip-bomb patterns: excessive expanded size, excessive compression ratio, too many entries, path traversal, absolute paths, and nested archives. The app must not extract archives outside an app-owned workspace.

## Enhanced Routing

Enhanced chooses the best available local model path for the document need.

| Input need | Preferred Enhanced path | Notes |
| --- | --- | --- |
| Complex digital PDF, table layout, multi-column document | Docling IBM models | CPU-capable path; may use acceleration where the Python/model stack supports it. |
| Scanned document page, research paper page, equations, code, document tables | Granite Docling MLX | Apple Silicon/Metal path. Optimized for document-to-Markdown, not arbitrary charts or logos. |
| Charts, plots, visual table extraction, key-value extraction, general visual understanding | Granite Vision 4.1 4B | Use task-specific prompts such as chart-to-CSV or chart summary. Heavy model; requires explicit capability gating. |

Granite Vision 3.2 2B is benchmark/reference-only until it proves a product role. On the current chart fixture, Granite Vision 4.1 4B is the stronger candidate.

## Capability Gates

Enhanced capability must be gated before purchase, download, and conversion.

| Capability | Required gate |
| --- | --- |
| Docling IBM models | Enough disk for model download, enough memory for conversion, Python runtime available. |
| Granite Docling MLX | Apple Silicon, Metal/MLX availability, enough disk, enough memory, validated model download. |
| Granite Vision 4.1 4B | Apple Silicon with MPS/Metal, larger disk and memory budget, validated model download, explicit user consent for the large model. |

The app must not allow a user to buy an Enhanced offer whose advertised capabilities cannot run on that Mac. If only part of Enhanced is available, the purchase surface must say so before purchase.

## Routing Order

The conversion classifier should select a bucket before conversion:

| Bucket | Basic recommendation | Enhanced recommendation |
| --- | --- | --- |
| Native/digital-simple | Native or MarkItDown fast path. | Same path unless quality scoring shows a model path improves output. |
| Digital-complex | Native/fast first with recoverable recommendation to Enhanced. | Docling IBM models, compared against native output when practical. |
| Scanned-document | Apple Vision OCR baseline. | Granite Docling MLX, compared against Vision OCR when practical. |
| Visual-chart-or-figure | Apple Vision OCR baseline plus metadata. | Granite Vision 4.1 4B with a task-specific extraction prompt. |
| Unknown | Start with safe Basic extraction and classify evidence. | Try the lowest-cost applicable Enhanced path first; avoid running every large model unless the user has enabled exhaustive comparison. |

For Enhanced users on capable machines, the app may run more than one candidate and choose by quality score. That behavior must remain bounded by memory pressure, liveness monitoring, cancellation, and privacy-redacted diagnostics.

## Privilege and Runtime Sandbox Policy

Upmarket must always run as the logged-in user. It must not request administrator credentials, install privileged helpers, use setuid/setgid binaries, or continue running if launched as root or with mismatched real/effective user or group IDs.

The advanced runtime must run in the signed `UpmarketRuntimeHelper` process, not in SwiftUI views or queue code. The helper must:

- have App Sandbox enabled and inherit the app sandbox;
- receive only copied app-workspace paths, never arbitrary original document paths;
- run conversion requests with offline environment defaults;
- allow network only for explicit model download requests;
- install Python runtime guards that block child process creation and network sockets during conversion;
- use a sanitized environment instead of inheriting developer shell variables such as `PYTHONPATH`, `PYTHONHOME`, or `DYLD_*`.

## Malicious Document Guards

Every conversion path must enforce cheap preflight limits before invoking heavyweight parsers or model runtimes.

| Threat | Guard |
| --- | --- |
| Oversized file | Reject inputs over the app hard cap before copying or parsing. |
| Extension spoofing | Check the first bytes/signature for binary formats before choosing a parser from the file extension. |
| ZIP bomb | Check archive entry count, expanded size, compression ratio, paths, and nested archives without extracting. |
| Huge PDF page canvas | Check PDF page count and declared page dimensions before rendering or model conversion. |
| Huge image dimensions | Check image dimensions and pixel count before decoding full raster data. |
| XML entity expansion | Use hardened XML parsing for fallback Office XML extraction. |
| Regex denial of service | Use bounded regex inputs and avoid nested quantifier patterns. |
| Native/C-extension overflows | Cap passwords, text block sizes, rendered page pixels, and image pixels before calling parser bindings. |
| Arbitrary code execution | Do not enable macros, embedded scripts, shell execution, or cloud/backends from user documents. |

## User-Facing Language

Normal UI should describe outcomes, not toolkits.

| Internal path | User-facing concept |
| --- | --- |
| PDFKit, Vision, ImageIO, AVFoundation, MarkItDown | Basic conversion |
| Docling IBM models | Advanced layout conversion |
| Granite Docling MLX | AI document conversion |
| Granite Vision 4.1 4B | Chart and visual extraction |

Implementation names belong in licenses, diagnostics, benchmark reports, and developer documentation.
