# ADR 0003: Isolate Advanced Conversion in a Helper Executable

## Status

Accepted for P0-002.

## Context

The packaged conversion runtime previously crashed inside the main app process during an import smoke path. Pinning runtime calls to one OS thread reduced that observed crash class, but it still left native package crashes, hard exits, and runtime stalls inside the Upmarket process.

## Decision

Move advanced conversion and model operations into `UpmarketRuntimeHelper`, a signed command-line helper embedded at `Upmarket.app/Contents/MacOS/UpmarketRuntimeHelper`.

The app keeps native PDF, OCR, media, metadata, StoreKit, and UI work in process. `PythonWorker` remains the app-side boundary, but it now calls `RuntimeHelperClient`, which launches the helper with a Codable JSON request and reads Codable JSON responses plus heartbeat events over standard I/O.

This is intentionally a helper executable rather than XPC for this release step:

- the request/response surface is short lived and operation oriented;
- one process per advanced operation gives simple crash and exit containment;
- the existing Xcode project can package and sign the helper with a small target and copy phase;
- no long-lived service lifecycle or listener protocol is needed yet.

The helper is sandboxed, linked to the embedded runtime, and allowed network client access only so explicit model download requests can run. Normal conversion requests force offline environment defaults. The app passes copied input paths and workspace paths only; user-selected original paths stay behind existing file access and workspace services.

## Contract

The helper accepts Codable JSON DTOs for:

- readiness/import smoke;
- document analysis;
- document conversion;
- model checks;
- offline mode;
- explicit model download.

Responses use neutral diagnostic codes such as `runtime.helper.crashed`, `runtime.helper.bad-exit`, `runtime.helper.invalid-response`, and `runtime.helper.stalled`. User-facing strings remain product-level and do not expose toolkit or package names.

## Consequences

The main app no longer imports `PythonKit` or links it into the app executable. `PythonKit` is target-scoped to `UpmarketRuntimeHelper`; the app embeds the runtime framework for the helper to load from `Contents/Frameworks`.

`RuntimeHelperClient` maps helper crashes, bad exits, invalid output, missing helper binaries, and heartbeat stalls to typed Swift errors. Cancellation terminates the helper process, while `ConversionRunner` continues to own workspace cleanup through the existing `defer` path.

XPC remains a possible future replacement if the helper needs a long-lived connection, richer progress streaming, or launchd-managed service semantics.
