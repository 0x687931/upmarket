# MCP and LM Studio Implementation Plan

## Objective

Make Upmarket available to LM Studio and other local MCP hosts as a document-to-Markdown tool without creating a second conversion engine.

The integration must preserve the existing product loop and boundaries:

- conversion still enters through `ConversionQueue` via the existing CLI handoff;
- StoreKit and AI availability checks remain app-owned;
- no Python, model, or converter implementation details are exposed to normal user-facing UI;
- the user can disable MCP advertisement from Preferences even if LM Studio still has an old `mcp.json` entry.

## Product Decision

Add a dedicated `LM Studio / MCP` section inside the existing Preferences `Conversion` tab. Do not add a new Preferences tab and do not introduce a general settings plugin framework.

The section is the settings plugin surface for this integration:

- Toggle: `Make Upmarket available to LM Studio`
- Status row: enabled, disabled, command missing, or app moved
- Button: `Add to LM Studio...`
- Button: `Copy mcp.json Snippet`
- Button: `Disable` or `Remove Instructions...` only if we can describe the behavior honestly

Disabling the toggle means:

- `upmarket-mcp` responds to `tools/list` with no tools;
- direct calls to hidden/previously cached tools return a product-level MCP tool error;
- existing LM Studio config is not silently edited or deleted.

This avoids hidden writes to `~/.lmstudio/mcp.json` and gives Upmarket a reliable local kill switch.

## Current Foundation

Upmarket already has the required conversion boundary:

- `Upmarket/UpmarketCLI/UpmarketCLI.swift` implements the CLI conversion command.
- `CLIConversionBroker` handles URL/app-group handoff in the main app.
- `ProgrammaticConversionAuthorization` keeps payment and AI gating app-owned.
- ADR 0004 requires scriptable conversion to stay behind the app and `ConversionQueue`.

The MCP server should wrap the CLI conversion command. It must not import app conversion services, call `ConversionRunner`, call Python, or duplicate format routing.

## External Requirements Checked

- LM Studio can act as an MCP host and loads local/remote servers from `mcp.json`: <https://lmstudio.ai/docs/app/mcp>
- LM Studio supports an `Add to LM Studio` deeplink for MCP server entries: <https://lmstudio.ai/docs/app/mcp/deeplink>
- LM Studio spawns one separate process per local MCP server and stores config at `~/.lmstudio/mcp.json` on macOS/Linux: <https://lmstudio.ai/blog/lmstudio-v0.3.17>
- MCP stdio transport is newline-delimited JSON-RPC over stdin/stdout, with logs on stderr only: <https://modelcontextprotocol.io/specification/2025-11-25/basic/transports>
- MCP tools are discovered through `tools/list` and invoked through `tools/call`: <https://modelcontextprotocol.io/specification/2025-11-25/server/tools>

## Architecture

### New Executable

Add a new Xcode command-line target:

```text
Upmarket/UpmarketMCP/
  UpmarketMCP.swift
  MCPJSONRPC.swift
  MCPToolRegistry.swift
  UpmarketCLIRunner.swift
  MCPAdvertisementState.swift
  UpmarketMCP.entitlements
```

Product name:

```text
upmarket-mcp
```

The target is embedded in:

```text
Upmarket.app/Contents/MacOS/upmarket-mcp
```

It resolves the sibling CLI at runtime:

```text
Upmarket.app/Contents/MacOS/upmarket-cli
```

The embedded CLI product must not be named `upmarket`, because the default
case-insensitive macOS filesystem treats that as the same path as the app
executable `Upmarket`.

Use `Process` with an argument array. Never invoke a shell.

### Transport and Protocol

Use local MCP stdio transport for v1.

Implement the narrow JSON-RPC subset needed by LM Studio:

- `initialize`
- `notifications/initialized`
- `ping`
- `tools/list`
- `tools/call`

The server writes only MCP JSON-RPC messages to stdout. Logs go to stderr.

Use no Node, Python, network server, daemon, or background listener in v1. This keeps packaging native and avoids a runtime dependency outside the app bundle.

### Advertisement State

Add a small shared state file:

```text
<App Group or fallback root>/MCP/advertisement.json
```

Shape:

```json
{
  "version": 1,
  "enabled": false,
  "updatedAt": "2026-06-04T00:00:00Z",
  "commandPath": "/Applications/Upmarket.app/Contents/MacOS/upmarket-mcp"
}
```

Default is disabled when the file is missing or unreadable.

Writers:

- `MCPIntegrationService` in the main app.

Readers:

- `upmarket-mcp`.

Use the same App Group root/fallback pattern as the CLI handoff. The CLI target already has App Group entitlement and is not sandboxed; `upmarket-mcp` should match that target shape unless release signing proves a stricter entitlement works.

### App Service

Add:

```text
Upmarket/Upmarket/Services/MCPIntegrationService.swift
```

Responsibilities:

- read/write `MCPAdvertisementState`;
- compute the current `upmarket-mcp` executable path from `Bundle.main.bundleURL`;
- build the LM Studio config entry;
- build the `lmstudio://add_mcp?...` deeplink;
- copy the `mcp.json` snippet to pasteboard;
- expose status for Preferences.

Do not read or edit `~/.lmstudio/mcp.json` in v1. App Sandbox makes that brittle and surprising.

### Preferences UI

Keep this inside `PreferencesView.conversionTab`.

Add a focused view component if needed:

```text
Upmarket/Upmarket/Views/MCPIntegrationSection.swift
```

Rows:

- Toggle `Make Upmarket available to LM Studio`
- Small status text:
  - `Disabled`
  - `Ready for LM Studio`
  - `MCP tool missing from this app build`
  - `Re-add to LM Studio if Upmarket was moved`
- Buttons:
  - `Add to LM Studio...` opens the generated deeplink.
  - `Copy mcp.json Snippet` copies only the server entry.

Suggested snippet:

```json
{
  "upmarket": {
    "command": "/Applications/Upmarket.app/Contents/MacOS/upmarket-mcp"
  }
}
```

The real path must be generated from the running app, not hard-coded.

### MCP Tools

Expose one tool in v1:

```text
convert_document_to_markdown
```

Input schema:

```json
{
  "type": "object",
  "properties": {
    "input_path": {
      "type": "string",
      "description": "Absolute path to a local document on this Mac."
    },
    "format": {
      "type": "string",
      "enum": ["markdown", "frontmatter", "json"],
      "default": "markdown"
    },
    "use_ai": {
      "type": "boolean",
      "default": false
    },
    "return_mode": {
      "type": "string",
      "enum": ["inline", "file"],
      "default": "inline"
    },
    "max_chars": {
      "type": "integer",
      "minimum": 1000,
      "maximum": 100000,
      "default": 20000
    }
  },
  "required": ["input_path"],
  "additionalProperties": false
}
```

Behavior:

- reject non-file paths and relative paths before invoking the CLI;
- call `upmarket-cli convert <input> -o <temp-output> --format <format> --force`;
- pass `--ai` only when `use_ai` is true;
- map CLI exit codes to MCP tool errors;
- return inline text only when it is under `max_chars`;
- for large output or `return_mode=file`, persist the result under an app-owned MCP output directory and return the file path plus metadata;
- clean stale MCP output files older than 24 hours on server startup.

Tool output should include structured metadata:

```json
{
  "status": "success",
  "format": "markdown",
  "returned": "inline",
  "output_path": null,
  "character_count": 12345
}
```

For compatibility, also include a concise text content block.

Do not expose resources or prompts in v1.

## LM Studio Flow

When the user clicks `Add to LM Studio...`:

1. Save advertisement state as enabled.
2. Generate the current absolute command path.
3. Base64-encode the JSON config for the `upmarket` server entry.
4. Open:

```text
lmstudio://add_mcp?name=upmarket&config=<base64-json>
```

If the user only copies the snippet, also enable advertisement unless the user has not toggled it on. The UI should make that state clear.

LM Studio will own tool-call confirmations. Upmarket still owns the disabled state and conversion authorization.

## Error Mapping

Map CLI exits to MCP `isError: true` tool results:

| CLI Exit | Meaning | MCP Message |
| --- | --- | --- |
| 1 | usage | `The tool arguments are invalid.` |
| 2 | input rejected | CLI stderr or `This file cannot be converted safely.` |
| 3 | purchase required | `Open Upmarket to unlock more conversions.` |
| 4 | AI unavailable | `Upmarket AI is not available for this conversion.` |
| 5 | conversion failed | CLI stderr or `Upmarket could not convert this document.` |
| 6 | output write failed | `Upmarket could not prepare the MCP output file.` |

Protocol errors are reserved for malformed MCP requests, unknown methods, and unknown tool names.

## Security and Privacy

- Default disabled.
- User must explicitly enable advertisement.
- The tool only accepts local absolute file paths.
- No remote URLs.
- No shell execution.
- No broad filesystem scan.
- No hidden edit to LM Studio config.
- No document contents in logs.
- No full source path in user-facing errors unless it is the explicit path supplied in the MCP call confirmation.
- MCP server cannot bypass StoreKit accounting because it calls `upmarket convert`.

## Work Packages

### MCP-001: ADR and Contract

Scope:

- Add ADR `docs/release/adr/0007-lm-studio-mcp-wrapper.md`.
- Capture the stdio Swift target decision, disabled advertisement semantics, and no direct conversion rule.
- Document the MCP tool schema and CLI exit-code mapping.

Acceptance:

- ADR explains why Node, Python, direct conversion, XPC, and HTTP server paths are rejected for v1.

Release gate:

- Gate A packaging
- Gate B conversion reliability
- Gate E if advertised publicly

### MCP-002: Shared Advertisement State

Scope:

- Add `MCPAdvertisementState`.
- Add `MCPIntegrationService`.
- Unit test default-disabled behavior, state persistence, invalid JSON fallback, generated command path, generated snippet, and deeplink encoding.

Acceptance:

- Disabled state survives app relaunch.
- Missing/unreadable state never advertises tools.

### MCP-003: Swift MCP Server Target

Scope:

- Add `UpmarketMCP` target and scheme.
- Implement stdio JSON-RPC handling.
- Implement `tools/list` disabled/ enabled behavior.
- Implement `convert_document_to_markdown` through the sibling `upmarket-cli` helper.
- Add a fake runner seam for tests.

Acceptance:

- Server stdout contains only JSON-RPC.
- Disabled `tools/list` returns `[]`.
- Enabled `tools/list` returns exactly one tool.
- Tool calls never use shell strings.
- CLI exit codes become MCP tool errors.

### MCP-004: Conversion Tab Settings Section

Scope:

- Add a dedicated `LM Studio / MCP` section inside `PreferencesView.conversionTab`.
- Wire the toggle to `MCPIntegrationService`.
- Add `Add to LM Studio...` and `Copy mcp.json Snippet`.
- Keep labels product-level: use `LM Studio`, `local tool`, and `document conversion`; avoid converter/runtime toolkit names.

Acceptance:

- The section appears in the Conversion tab.
- Toggle disable immediately changes what `upmarket-mcp tools/list` advertises.
- Deeplink uses the actual running app path.
- Copy snippet contains only the `upmarket` server entry.

### MCP-005: Packaging and Validation Hooks

Scope:

- Embed `upmarket-mcp` beside `upmarket-cli` in the app bundle.
- Update release/package verification to assert `Upmarket`, `upmarket-cli`, and `upmarket-mcp` exist without case-insensitive path collisions and are signed.
- Add focused CI validation for MCP JSON-RPC smoke.

Acceptance:

- `xcodebuild -project Upmarket/Upmarket.xcodeproj -scheme UpmarketMCP -destination 'platform=macOS,arch=arm64' build` passes.
- `scripts/ci/gate.sh quick` passes.
- Manual LM Studio load shows the tool only when enabled.
- A real `convert_document_to_markdown` call returns Markdown for a known fixture.

## Validation Matrix

Required before merging:

```sh
xcodebuild -project Upmarket/Upmarket.xcodeproj -scheme UpmarketMCP -destination 'platform=macOS,arch=arm64' build
xcodebuild -project Upmarket/Upmarket.xcodeproj -scheme UpmarketCLI -destination 'platform=macOS,arch=arm64' build
scripts/ci/gate.sh quick
```

Manual validation:

```sh
upmarket-cli convert tests/corpus/<fixture>.pdf -o /tmp/upmarket-fixture.md --force
```

MCP validation:

- launch `upmarket-mcp` under MCP Inspector;
- verify disabled state returns no tools;
- enable from Preferences;
- add to LM Studio using the generated deeplink;
- ask LM Studio to convert a local fixture;
- disable from Preferences and verify LM Studio no longer sees Upmarket tools after reload, and direct calls fail.

Release-candidate validation:

```sh
scripts/ci/gate.sh minor
```

Use `scripts/ci/gate.sh runtime` if MCP packaging changes touch app bundle signing, entitlements, helper embedding, or runtime helper behavior.

## Rollback

- Remove `UpmarketMCP` target, scheme, and embedded executable.
- Remove `MCPIntegrationService` and the Conversion-tab section.
- Leave `upmarket` CLI and CLI handoff untouched.
- Existing LM Studio `mcp.json` entries will fail to launch or expose no tools; publish a support note telling users to remove the `upmarket` MCP entry from LM Studio.

## V1 Decisions

- `return_mode=file` writes into `<App Group or fallback root>/MCP/Outputs`; `upmarket-mcp` removes output files older than 24 hours on startup.
- MCP calls default to deterministic `format=markdown`; they do not inherit `OutputPreference.shared.mode`.
- `use_ai` is exposed as an optional `false` default. The app-owned CLI authorization path remains the source of truth for availability and payment checks.
