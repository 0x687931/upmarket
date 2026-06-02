# Upmarket Project Vision

## Product North Star

Upmarket does one thing well: convert documents to clean Markdown on a Mac, privately and reliably.

The product promise is simple:

- Drop or choose a document.
- Watch clear progress.
- Get useful Markdown.
- Copy or save the result.
- Pay once for durable value.

Every feature must support that loop. If a feature does not make conversion easier, more reliable, safer, or easier to pay for, it waits.

## Engineering Philosophy

Upmarket follows a mix of Linus-style minimalism and DHH-style product monolith thinking.

Linus-style means:

- Keep code obvious.
- Prefer direct data flow over clever abstraction.
- Delete dead paths and speculative framework code.
- Avoid protocol forests, generic service layers, and architecture for architecture's sake.
- Make failure visible and debuggable.

DHH-style means:

- Build a coherent app, not a pile of disconnected micro-components.
- Keep features together when that makes the product easier to understand.
- Optimize for a solo maintainer plus Codex AI.
- Use boring, native platform tools wherever practical.
- Treat release quality as part of the product, not an afterthought.

## Architecture Direction

The target is a small macOS monolith with hard boundaries:

```text
Upmarket/Upmarket/
  Views/              SwiftUI presentation and user gestures
  Services/           Concrete app services and coordinators
  Domain/             Plain structs/enums when shared models outgrow a service file
  Infrastructure/     Hard runtime adapters such as a future Python helper
  Resources/          Assets, localisation, licenses, privacy manifest
```

Rules:

- UI renders state and sends actions.
- Conversion has one entry point.
- Queue items own their own progress, result, and error.
- Python is behind one boundary.
- StoreKit is behind one boundary.
- File access is behind one boundary.
- Diagnostics are privacy-redacted by default.
- User-facing copy describes product behavior, not implementation toolkits. Internal engines and third-party components belong in logs, diagnostics, and licenses, not normal UI.

The detailed boundary map is `docs/release/ARCHITECTURE_BOUNDARIES.md`.
The product tier and conversion routing policy is `docs/release/TIER_AND_ROUTING_POLICY.md`.

## Product Scope Discipline

Keep:

- Shelf and menu bar workflow.
- StoreKit monetization.
- Preferences/paywall.
- Python/Docling value proposition.
- Native Apple APIs where they reduce risk.
- Release pipeline and diagnostics.
- Apple storage correctness for iCloud Drive, File Provider locations, security-scoped URLs, app containers, and App Group handoff.

Challenge or defer:

- Extra purchase models.
- Extra conversion entry points.
- Remote behavior switches.
- Background magic users cannot see.
- New dependencies without a release/rollback story.
- Exposing toolkit names or implementation internals to end users outside licenses and explicit diagnostic previews.

## Maintainer Model

This repository is maintained by one non-programmer owner working with Codex AI. The codebase must therefore be:

- readable in small chunks;
- documented at the decision level;
- testable without manual heroics;
- safe for multiple AI agents to touch in parallel;
- strict about ownership boundaries and release gates.

Prefer fewer files with clear names over many tiny abstractions. Prefer one tested path over three partial paths.
