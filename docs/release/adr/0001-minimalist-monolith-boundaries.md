# ADR 0001: Minimalist Monolith Boundaries

## Status

Accepted

## Context

Upmarket is maintained by one non-programmer owner with Codex AI support. The app must stay small enough to understand, but reliable enough for paid App Store users. Earlier implementation work left UI, AppKit file operations, conversion orchestration, and duplicate menu-bar code closer together than the release plan allows.

## Decision

Use a coherent macOS monolith with concrete boundaries:

- `Views/` renders UI and sends user intent.
- `Services/` owns concrete app behavior.
- `Domain/` is introduced only when shared plain models need a home.
- `Infrastructure/` is introduced only for hard runtime boundaries such as a future Python helper.
- Release automation and task orchestration live under `docs/release/` and `scripts/`.

Do not introduce TCA, Clean Architecture scaffolding, dependency-injection frameworks, or protocol-first service trees. Use native Apple APIs directly behind concrete services.

## Consequences

This keeps the codebase nimble and easy for Codex to change safely. The tradeoff is that some services will be larger than in a heavily layered app. That is acceptable while the service has one clear job and tests or release hooks cover the behavior.

## Follow-up

- P0-002 moves Python execution behind a stronger bridge/helper boundary.
- P0-003 replaces singleton conversion result polling with per-job queue state.
- P0-007 reviews StoreKit pack accounting.
- P0-008 adds diagnostics boundaries.
