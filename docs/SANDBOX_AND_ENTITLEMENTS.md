# Sandbox & Entitlements

Upmarket runs in the App Sandbox, a security boundary that restricts access to system resources. This document explains what users can and cannot do, and why.

## What Users CAN Do

### 1. Choose and Convert Documents
- Users can drag-and-drop documents onto Upmarket or use "Choose…" to select files.
- Supported formats: PDF, DOCX, PPTX, XLSX, HTML, images (JPEG, PNG, etc.), audio, video.
- Upmarket gets read access to chosen files via `NSOpenPanel` (user-initiated file picker).

### 2. Save Markdown Results
- After conversion, users can copy the Markdown to clipboard or save to a file.
- Save location is user-chosen via `NSSavePanel` (user-initiated file picker).
- Upmarket gets write access only to the location the user selected.

### 3. Use Watched Folders (Paid Feature)
- Upmarket can monitor folders the user explicitly grants access to.
- When new documents are placed in a watched folder, Upmarket automatically converts them.
- Access is via security-scoped bookmarks (durable, persistent per session).

### 4. Download First-Party Models
- Users on paid tiers can download optional AI models for enhanced conversion.
- Models are stored in `~/Library/Application Support/Upmarket/models/` with user permission.
- Download uses the network entitlement (`com.apple.security.network.client`).

### 5. Share Quick Actions (macOS Finder)
- Users can right-click a file in Finder and select "Convert to Markdown" (Quick Action).
- The Quick Action extension uses the same sandbox as the app via App Group (`group.com.upmarket.app`).

## What Users CANNOT Do (Sandbox Boundaries)

### ❌ Access Arbitrary Folders
- Upmarket cannot enumerate or read files in `~/Documents`, `~/Downloads`, or other system folders without explicit user permission.
- Users must grant access via file picker or drag-and-drop, file by file.

### ❌ Execute Scripts or Commands
- Upmarket cannot run shell scripts, open Terminal, or invoke arbitrary system processes.
- Python is embedded and sandboxed; it cannot access files outside the app's sandbox.

### ❌ Access User Data from Other Apps
- Upmarket cannot read passwords, browser history, email, or data from other apps.
- Upmarket cannot modify system preferences or install software.

### ❌ Persistent Network Access
- Upmarket has network access only for model downloads.
- It cannot make general HTTP/HTTPS requests to arbitrary servers.
- No cloud processing, no telemetry, no API calls (100% offline after setup).

### ❌ Access Microphone or Camera
- Upmarket does not request or use microphone or camera.
- (It can process audio files that users provide, but cannot record new audio.)

## Entitlements

The app declares these entitlements in `Upmarket/Upmarket/Upmarket.entitlements`:

| Entitlement | Purpose | When Used |
| --- | --- | --- |
| `com.apple.security.app-sandbox` | Enable App Sandbox | Always |
| `com.apple.security.files.user-selected.read-write` | User-chosen file I/O | Drag-drop, file picker, save dialog |
| `com.apple.security.application-groups` | Shared container with Quick Action | Quick Action extension communication |
| `com.apple.security.network.client` | Network access for model downloads | Downloading optional AI models |

### Network Entitlement Details

The network entitlement is intentionally **not** granted by default in the signed app. It is only requested if a user explicitly attempts to download a first-party model. This ensures the app never makes network requests without user knowledge.

In App Store review, this is declared under "Network" → "Outgoing Connections" as: *"Outbound connections to download optional AI model weights from Apple's official model distribution servers."*

## Security Properties

### What the Sandbox Guarantees

1. **File Access Isolation:** Upmarket can only read/write files the user explicitly selected.
2. **No Privilege Escalation:** Upmarket runs with user privileges; it cannot gain admin or root access.
3. **No Data Exfiltration:** Even if Upmarket were compromised, the attacker cannot:
   - Access files outside the chosen paths
   - Make general network requests (network entitlement is model-download only)
   - Execute arbitrary commands
   - Access other apps' data

### What the Sandbox Does NOT Guarantee

1. **App Integrity:** The sandbox doesn't prevent bugs in Upmarket's code (e.g., a crash when processing a malformed PDF).
2. **Explicit Consent:** Users who grant access to a watched folder cannot un-grant it until the app is uninstalled (limitation of macOS security-scoped bookmarks).

## Testing Sandbox Behavior

- **Local Testing:** Run `scripts/dev/run_app.sh` to launch the app with sandboxing enabled.
- **Entitlement Verification:** `scripts/ci/verify_entitlements.sh` checks that declared entitlements match the code's usage.
- **App Store Review:** TestFlight and App Store both enforce the same sandbox, so testing there is equivalent to production.

## User-Facing Documentation

The app's App Store listing includes:

> **Privacy:** Upmarket processes documents locally on your Mac. No data leaves your device. Model downloads (optional, paid tier) connect to Apple's servers for model weights only. Upmarket does not collect personal data, browsing history, or file contents.

This is accurate: all conversion happens on-device (Python subprocess), and only model downloads use the network.
