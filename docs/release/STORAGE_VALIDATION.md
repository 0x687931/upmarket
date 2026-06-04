# Storage Validation

Upmarket must handle user-selected documents through Apple storage APIs without exposing implementation details. All conversion reads should be copied into an app-owned workspace before processing. Delayed reads, Quick Action handoff, and saved output must use security-scoped access, security-scoped bookmarks, or copied app-owned files.

## Required Scenarios

Run these checks before v1.0 release and after any file-access, Quick Action, sandbox, or save-location change:

| Scenario | Expected Result |
| --- | --- |
| Local file in Documents | Converts or returns a product-level file access error. |
| Desktop/Documents in iCloud, downloaded locally | Converts after security-scoped access. |
| iCloud file evicted/not downloaded | Shows "not available on this Mac" style copy; no raw path or toolkit name. |
| File Provider location such as Dropbox/Google Drive/OneDrive | Converts when provider has materialized the file; otherwise shows unavailable copy. |
| External volume under `/Volumes` | Converts when mounted and readable; fails cleanly after unmount. |
| Network volume | Converts when mounted and readable; fails cleanly on disconnect. |
| Read-only source folder | Conversion can read; same-folder save falls back to Save panel. |
| Denied save location | Save panel fallback or no-op with recoverable user action. |
| Finder Quick Action | Extension copies selected files into App Group handoff; main app never trusts URL query paths. |
| Stale App Group handoff | App ignores invalid manifests and cleanup policy removes stale copied files. |
| Conversion history record | Completed conversions write JSON under `Application Support/Upmarket/History` with display filename, metadata, and Markdown only. No full source paths, passwords, bookmarks, or diagnostics are stored. |
| Corrupt history record | App ignores the bad JSON record and launches without crashing. |
| Clear conversion history | Preferences removes stored history JSON and leaves active conversion queue state untouched. |
| Add watched folder | Preferences requires explicit folder selection and stores a security-scoped bookmark, not a plain raw path setting. |
| Watched folder new supported file | Dropping a stable supported file into the watched folder enqueues exactly one conversion through the normal queue. |
| Watched folder unsupported file | Unsupported files are ignored without exposing raw paths or implementation details. |
| Watched folder output folder | A chosen output folder uses its own security-scoped bookmark and writes formatted output without overwriting existing files. |
| Remove watched folder | Removing a watched folder stops monitoring and does not delete user documents or history records. |

## Copy Audit

User-facing UI, errors, support reports, onboarding, App Store copy, and paywall text must describe product behavior only. Do not mention internal toolkits, package names, helper runtimes, raw local paths, or implementation stages except in licenses and explicit diagnostic previews.

## Native API Rules

- Use `NSOpenPanel`/`NSSavePanel` only inside concrete services.
- Use `startAccessingSecurityScopedResource()` around user-selected reads/writes.
- Persist security-scoped bookmarks for chosen save folders or delayed access.
- Copy conversion inputs into `Application Support/Upmarket/Workspaces`.
- Store conversion history only under `Application Support/Upmarket/History`, and keep it clearable from Preferences.
- Keep Quick Action handoff in the App Group container and pass opaque IDs only.
- Watched folders must be opt-in, non-recursive for v1, and backed by security-scoped bookmarks.
