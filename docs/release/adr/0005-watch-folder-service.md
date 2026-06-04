# ADR 0005: Opt-In Watch Folder Service

Date: 2026-06-04

## Status

Accepted

## Context

The Panic review calls for watch folders so Upmarket can act as background
document-conversion infrastructure. This adds a long-lived file-system service,
so it must preserve the existing boundaries: conversion still enters through
`ConversionQueue`, sandbox access comes from explicit user selection, and no
raw broad paths are persisted without security-scoped bookmarks.

## Decision

Add a concrete `WatchedFolderService` owned by the app process. Users opt in
from Preferences by selecting specific folders through `NSOpenPanel`. The
service stores security-scoped bookmarks plus display names, watches only the
selected directory level, debounces file-system events, waits for stable file
metadata, and then calls `ConversionQueue.convert`.

Watched-folder output is explicit per folder:

- history only;
- same folder as the watched input;
- a chosen output folder stored as its own security-scoped bookmark.

Completion notifications are an opt-in local notification toggle per watched
folder.

## Alternatives Considered

- Recursive FSEvents over broad roots: rejected because it risks surprising
  background conversion and broad filesystem access.
- A separate helper daemon: rejected because it would add a second long-lived
  process and make conversion ownership less obvious.
- CLI polling from launch agents: rejected because it duplicates scheduling and
  would be harder to package cleanly.

## Consequences

- The watcher is app-lifetime only. It resumes when Upmarket launches and valid
  bookmarks resolve.
- Duplicate events are de-duped in memory by file name, size, and modification
  time.
- Existing files are not bulk imported when a folder is added; conversion is
  driven by subsequent stable file events or explicit scans in tests.
- Output writes use product-level formatting at the boundary and do not change
  raw conversion output.

## Validation

- `scripts/ci/gate.sh quick`
- `scripts/ci/gate.sh minor` before release because this touches background
  file access and Preferences.
- Manual storage checks for local, cloud-downloaded, external, and read-only
  folder cases in `docs/release/STORAGE_VALIDATION.md`.

## Rollback

Remove `WatchedFolderService`, the Preferences Watch Folders section, and the
app startup call. Existing stored bookmark data is ignored if the service is no
longer present.
