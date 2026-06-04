# Architecture Decision Record

## Title

Add CLI Through URL Handoff Broker

## Status

Accepted

## Context

PR-6 in `docs/release/PANIC_REVIEW_IMPLEMENTATION_PLAN.md` requires an
`upmarket` command-line tool for terminal, automation, and agent workflows. The
main risk is accidentally creating a second conversion engine or a filesystem
shortcut around app authorization. Upmarket must keep one conversion entry
point, preserve sandbox boundaries, and keep user-facing errors product-level.

## Decision

Add a small `upmarket` command-line target that acts as a client to the main
app. The CLI copies the selected input into an App Group handoff directory,
writes a JSON request, launches `upmarket://convert?cli=<uuid>`, waits for a
JSON response, and writes the formatted output atomically.

The main app owns authorization and conversion. It reads the handoff, uses the
same programmatic authorization path as App Intents, runs
`ConversionQueue.shared.convert`, formats the result, and writes a response.
The handoff contains display filenames only, never full source paths.

## Alternatives Considered

- App Intent bridge: attractive because Shortcuts already works, but there is
  no stable direct command-line invocation of an app intent with file output and
  error codes suitable for scripts.
- XPC broker: stronger for bidirectional progress, but too much packaging and
  protocol surface for the first CLI.
- Direct CLI conversion: rejected because it would duplicate conversion routing,
  authorization, runtime helper handling, and privacy policy outside the app.
- Do nothing: keeps the app UI-only and leaves the Panic/developer integration
  gap open.

## Tradeoffs

Benefits:

- Keeps `ConversionQueue` as the only conversion entry point.
- Reuses App Intent authorization behavior for CLI conversion.
- Avoids trusting raw custom-URL file paths.
- Keeps CLI output deterministic for scripts and future Nova integration.

Costs:

- Requires the app to be installed and launchable for CLI conversion.
- First version polls a response file instead of streaming progress.
- Installation still needs an explicit Preferences flow before release.

## Minimality Check

This is the smallest acceptable solution because the existing Quick Action
already uses an opaque URL handoff pattern. PR-6 only needs a reliable first CLI,
not a new daemon, XPC service, progress UI, or installer.

This ADR does not add watch folders, shell completions, Nova integration, or a
silent `/usr/local/bin` installer.

## Release and Test Impact

Affected release gates:

- Gate A packaging
- Gate B conversion reliability
- Gate D authorization if paid behavior changes
- Gate E privacy/listing copy if CLI is advertised

Required validation:

- `xcodebuild -project Upmarket/Upmarket.xcodeproj -scheme upmarket -destination 'platform=macOS,arch=arm64' build`
- `scripts/ci/gate.sh quick`
- Focused unit tests for request/response mapping and output formatting
- Manual conversion through the built `upmarket` tool before release

Rollback plan:

- Remove the `upmarket` target, the CLI URL handler branch, and
  `CLIConversionBroker`.
- Leave the existing Quick Action `handoff` URL path untouched.

## Follow-Up Tasks

- [ ] Add an explicit Preferences installer for the command-line tool.
- [ ] Add CLI progress reporting after the handoff contract is stable.
- [ ] Build the Nova extension against `upmarket convert`.
