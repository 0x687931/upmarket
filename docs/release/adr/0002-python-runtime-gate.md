# ADR 0002: Python Runtime Gate

## Status

Accepted for P0-002.

## Context

Upmarket depends on embedded CPython and Python packages for fallback document conversion and model management. Direct `Python.import` calls from multiple Swift services risk unsafe interpreter access, unclear readiness behavior, and inconsistent error handling.

## Decision

Use a single actor-backed `PythonRuntime` as the in-process Python gate. `PythonBridge` remains a SwiftUI-observable readiness facade, and `PythonWorker` is the only conversion/model service allowed to call Python modules.

The runtime gate:

- configures `PYTHONHOME`, `PYTHONPATH`, model cache paths, and offline environment defaults;
- serializes Python execution through actor isolation;
- maps setup/import/call failures to typed `PythonBridgeError` values;
- allows network only around explicit model download calls by temporarily enabling download mode.

We are not adding an XPC helper in this step. That remains the escalation path if fault-injection or real crash data proves in-process Python can crash or wedge the app despite the serialized gate.

## Consequences

Swift call sites now use async Python worker methods. Architecture validation fails if future Swift files import `PythonKit` or call `Python.import` outside `PythonBridge.swift` and `PythonWorker.swift`.

P0-004 still owns full model manifest validation, staged downloads, and atomic promotion.

## 2026-06-01 Runtime Thread Update

Corpus probing reproduced a process crash when the packaged converter was imported through `Upmarket.app` and PythonKit, while the same bridge imported successfully through CLI Python and the bundle smoke script. Crash reports showed `PyImport_ImportModule` failing inside CPython allocation before document-specific converter code ran.

The immediate mitigation is a single long-lived `PythonRuntimeThread`: runtime setup, imports, environment-scoped calls, downloads, and conversions all execute on one OS thread behind `PythonRuntime`. This preserves the minimalist in-process gate and prevents Swift concurrency from moving Python C API calls across cooperative executor threads.

This does not replace P0-002 helper isolation. A dedicated thread fixes the observed import crash class; XPC or another signed helper is still required before release to contain native crashes or hard process exits from third-party runtime code.
