# Diagnostic Components

Runtime logs, support reports, and user-approved diagnostics use neutral component codes instead of package or toolkit names. This keeps user-facing support material product-level while preserving a developer mapping for debugging.

## Public Diagnostic Codes

| Code | Meaning | Developer Mapping |
| --- | --- | --- |
| `file.access` | The app could not read or copy the selected file. | `FileAccessService`, security-scoped access, app workspace copy |
| `file.password` | The document requires a password. | PDF password handling before extraction |
| `file.too-large` | The input exceeded the configured safety limit. | `AppWorkspace.maxInputBytes` |
| `file.unavailable` | The selected file is not locally available. | iCloud/File Provider/external storage availability checks |
| `job.cancelled` | User or queue cancelled conversion. | `ConversionQueue` cancellation |
| `job.no-progress` | Conversion heartbeat stopped advancing. | `ConversionQueue` liveness classification |
| `conversion.failed` | Generic conversion failure. | See adjacent stage and component logs |
| `runtime.bridge` | Advanced conversion runtime failed before a typed subcode was available. | Isolated helper and packaged runtime |
| `runtime.helper.unavailable` | Advanced runtime helper is missing or cannot launch. | Embedded helper packaging/signing |
| `runtime.helper.crashed` | Advanced runtime helper terminated by signal. | Helper process crash report |
| `runtime.helper.bad-exit` | Advanced runtime helper exited nonzero. | Helper exit status and logs |
| `runtime.helper.invalid-response` | Advanced runtime helper returned unreadable data. | Codable DTO/version mismatch |
| `runtime.helper.stalled` | Advanced runtime helper stopped heartbeating. | Helper liveness monitor |
| `runtime.helper.runtime-unavailable` | Advanced runtime failed to initialise inside the helper. | Embedded runtime startup/environment |
| `runtime.helper.component-unavailable` | A required advanced runtime component could not load. | First-party bridge or model manager package |
| `runtime.helper.call-failed` | Advanced runtime call failed after startup. | Helper invocation or runtime exception |

## Rules

- Normal UI copy must not show package, framework, or toolkit names.
- OSLog messages may include these neutral codes because users can include logs in support reports.
- Developer docs, benchmark artifacts, and licenses may name packages and frameworks.
- Add a code here before adding a new runtime diagnostic category.
