# ADR 0007: LM Studio MCP Wrapper

Date: 2026-06-04

## Status

Accepted

## Context

Upmarket needs to be available to LM Studio and other local MCP hosts as a
document-to-Markdown tool. The risk is creating another conversion path or a
long-lived local service that bypasses the app's existing conversion,
authorization, sandbox, and privacy boundaries.

Upmarket already has a scriptable CLI conversion command that copies input
into an App Group handoff, launches the app URL handler, and waits for the main
app to authorize and run `ConversionQueue.shared.convert`.

## Decision

Add a small `upmarket-mcp` command-line target that implements MCP over stdio
and wraps the existing CLI conversion command. When embedded in the app bundle,
that helper is named `upmarket-cli`; `upmarket` would collide with the app
executable `Upmarket` on the default case-insensitive macOS filesystem.

The main app owns a dedicated `LM Studio / MCP` section inside the Preferences
Conversion tab. That section writes an App Group advertisement state file and
offers an `Add to LM Studio` deeplink plus a copyable `mcp.json` snippet.

MCP advertisement is disabled by default. When disabled, `upmarket-mcp` still
starts but returns no tools from `tools/list`; direct calls to the known
conversion tool return a product-level tool error. The app does not edit
`~/.lmstudio/mcp.json`.

## Alternatives Considered

- Node or Python MCP server: rejected because it adds an external runtime
  dependency for a native macOS app and increases packaging/support surface.
- Direct conversion inside the MCP server: rejected because it would duplicate
  routing, StoreKit authorization, Python/runtime isolation, file access, and
  privacy policy.
- XPC broker: stronger for bidirectional progress, but too much protocol and
  packaging surface for the first MCP integration.
- Streamable HTTP server: rejected for v1 because a local stdio server is enough
  for LM Studio and avoids a network listener.
- Editing LM Studio's `mcp.json`: rejected because the app sandbox and user
  consent model make hidden writes brittle and surprising.

## Consequences

- LM Studio integration depends on the same CLI contract used by terminal users
  and agent workflows.
- Moving Upmarket after adding it to LM Studio requires the user to re-add the
  MCP entry, because LM Studio stores the absolute command path.
- Tool output may be too large for local model context, so the MCP tool can
  return a persisted app-owned output file instead of inline text.
- The quick gate includes a stdio smoke test for disabled and enabled tool
  discovery.

## Validation

- `xcodebuild -project Upmarket/Upmarket.xcodeproj -scheme UpmarketMCP -destination 'platform=macOS,arch=arm64' build`
- `xcodebuild -project Upmarket/Upmarket.xcodeproj -scheme UpmarketCLI -destination 'platform=macOS,arch=arm64' build`
- `scripts/ci/validate_mcp_server.py /path/to/Upmarket.app`
- `scripts/ci/gate.sh quick`
- Manual LM Studio add/reload before public advertising.

## Rollback

Remove the `UpmarketMCP` target, the app copy phase entry for `upmarket-mcp`,
`MCPIntegrationService`, and the Preferences section. Leave the existing
CLI handoff untouched.
