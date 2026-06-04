# ADR 0006: Nova Extension Wraps the Upmarket CLI

Status: Accepted

## Context

The Panic review asks for a Nova integration, but the app already has one
conversion entry point and the CLI handoff exists specifically to support
scriptable conversion without duplicating conversion logic.

Nova extensions declare their commands in `extension.json`, register matching
JavaScript handlers, and can run external tools through the Process entitlement.

## Decision

Add `Nova/Upmarket.novaextension` as a thin extension bundle. The extension:

- invokes `upmarket convert` with a selected or current file;
- opens the result in a new Nova document, inserts it at the cursor, or copies it;
- maps CLI exit codes to product-level messages;
- declares only the entitlements required for process, clipboard, and temporary
  file access.

It does not call app services directly, inspect document contents beyond the
selected file path handed to the CLI, or duplicate conversion logic in
JavaScript.

## Consequences

Panic ecosystem integration now depends on the same CLI contract used by
terminal users and agents. If the CLI changes its exit-code contract or output
mode names, the Nova extension validator and manual Nova smoke test must be
updated in the same change.

Manual Nova validation remains required before shipping or advertising the
extension because Nova itself is outside the Xcode test target.
