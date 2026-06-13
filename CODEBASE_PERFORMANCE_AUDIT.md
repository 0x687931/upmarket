# Codebase Performance Audit: Pattern Consistency Report

**Scope**: 141 Swift files across Upmarket app  
**Date**: 2026-06-13  
**Status**: 📊 26 issues identified across 15 files

---

## Executive Summary

The codebase has **inconsistent patterns** for handling file I/O, directory operations, and blocking tasks:

- ✅ **Good**: Async/await is used in conversion paths
- ⚠️ **Mixed**: Some file operations are async, others are synchronous
- ❌ **Problem**: Several blocking operations on main thread or in sync contexts

**Total work to standardize**: ~25 hours

---

## 🔴 CRITICAL ISSUES (Main-Thread Blocking)

### 1. SavePreference.swift — Multiple Blocking Writes
**File**: `Services/SavePreference.swift` (Lines 95, 113, 150)

```swift
// ❌ BLOCKING on main thread
try markdown.write(to: saveURL, atomically: true, encoding: .utf8)
```

**Context**: SavePreference is a @MainActor class; calls happen on main thread  
**Frequency**: 3 locations  
**Impact**: 100-500ms stall on save  
**Fix**: Use FileWriteService or extract to async method

---

### 2. WatchedFolderService.swift — Auto-Conversion Writes
**File**: `Services/WatchedFolderService.swift` (Lines 317, 414)

```swift
// ❌ BLOCKING on main thread (class is not actor-isolated, but writes are sync)
try Data(formatted.text.utf8).write(to: outputURL, options: .atomic)
```

**Context**: Writes converted files to watched folders  
**Frequency**: 2 locations  
**Impact**: File write blocks folder monitoring  
**Fix**: Use FileWriteService

---

### 3. ConversionHistoryStore.swift — History Recording
**File**: `Services/ConversionHistoryStore.swift` (Line 111)

```swift
try data.write(to: url, options: .atomic)
```

**Context**: Records conversion history after completion  
**Frequency**: 1 location  
**Impact**: 10-50ms stall after conversion finishes  
**Fix**: Use FileWriteService

---

### 4. PackCreditLedger.swift — Ledger Persistence
**File**: `Services/PackCreditLedger.swift` (Line 130)

```swift
try data.write(to: fileURL, options: .atomic)
```

**Context**: Writes in-app purchase ledger  
**Frequency**: 1 location  
**Impact**: Blocks purchase flow  
**Fix**: Use FileWriteService

---

## 🟠 HIGH: File Metadata Reads (Should Be Async)

### 5. FirstPartyModelDownloadService.swift
**File**: `Services/FirstPartyModelDownloadService.swift` (Line 399)

```swift
let values = try url.resourceValues(forKeys: [.fileSizeKey])
```

**Context**: Reading model file size during download validation  
**Status**: Sync in background task (acceptable but could use FileSizeReader)  
**Fix**: Replace with `FileSizeReader.shared.readSize()`

---

### 6. NativeMetadataExtractor.swift
**File**: `Services/NativeMetadataExtractor.swift` (Line 74)

```swift
let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
```

**Context**: Reading file metadata for native extraction  
**Status**: Sync call  
**Fix**: Replace with `FileSizeReader.shared.readSize()`

---

### 7. WatchedFolderService.swift — File Signature Check
**File**: `Services/WatchedFolderService.swift` (Lines 347-352)

```swift
guard let values = try? url.resourceValues(forKeys: [
    .isDirectoryKey,
    .isRegularFileKey,
    .fileSizeKey,
    .contentModificationDateKey
]) else { return nil }
```

**Context**: Checking file stability before processing  
**Frequency**: Called repeatedly during file watching  
**Status**: Sync, could block if called frequently  
**Fix**: Create FileSignatureReader actor for efficient caching

---

### 8. AppDelegate.swift — Cleanup
**File**: `AppDelegate.swift` (Line 217)

```swift
let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
```

**Context**: Cleanup on app launch  
**Status**: Acceptable (launch-time operation)  
**Fix**: Can stay sync (not performance-critical)

---

### 9. Diagnostics.swift — Snapshot
**File**: `Services/Diagnostics.swift` (Line 200)

```swift
(try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
```

**Context**: Building diagnostic snapshot  
**Status**: Acceptable (diagnostic, not user-facing)  
**Fix**: Can stay sync

---

### 10. AppWorkspace.swift — Cleanup
**File**: `Services/AppWorkspace.swift` (Line 66)

```swift
let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
```

**Context**: Cleaning up work directory  
**Status**: Acceptable (cleanup operation)  
**Fix**: Can stay sync

---

## 🟠 HIGH: Directory Enumeration (Currently Sync)

### 11. FirstPartyModelDownloadService.swift — Model Search
**File**: `Services/FirstPartyModelDownloadService.swift` (Lines 329+)

```swift
let enumerator = fileManager.enumerator(at: directoryURL, includingPropertiesForKeys: nil)
for entry in enumerator { ... }  // Recursively enumerates
```

**Context**: Finding models in directory during downloads  
**Status**: Sync, potentially slow on large directories  
**Frequency**: Once per model download  
**Fix**: Replace with `DirectorySizeReader` or similar async utility

---

### 12. ModelManager.swift — Directory Size (ALREADY FIXED)
**File**: `Services/ModelManager.swift` (Lines 249-256)

```swift
// ⚠️ Already identified in PERFORMANCE_REVIEW.md #6
// Will be replaced with DirectorySizeReader
```

---

## 🟡 MEDIUM: Pasteboard Operations (Async Opportunity)

### 13. FileAccessService.swift — Multiple Pasteboard Ops
**File**: `Services/FileAccessService.swift` (Lines 174-190)

```swift
NSPasteboard.general.clearContents()
NSPasteboard.general.setString(markdown, forType: .string)
```

**Frequency**: 3 locations (copyMarkdown, copySupportReport, copyFilePath)  
**Status**: Already in FileWriteService (ready to integrate)  
**Fix**: Replace with `FileWriteService.shared.copyMarkdown()`

---

### 14. MCPIntegrationService.swift — Pasteboard Copy
**File**: `Services/MCPIntegrationService.swift` (Lines 84-85)

```swift
NSPasteboard.general.clearContents()
NSPasteboard.general.setString(text, forType: .string)
```

**Context**: MCP server copies text to pasteboard  
**Status**: Not critical (background service)  
**Fix**: Optional; can stay sync

---

## 🟡 MEDIUM: File Removal Operations (Should Be Async)

### 15. AppDelegate.swift — Cleanup
**File**: `AppDelegate.swift` (Line 220)

```swift
try? FileManager.default.removeItem(at: entry)
```

**Context**: Cleanup on app launch  
**Status**: Acceptable (not frequent, launch-time)  
**Fix**: Can stay sync (low frequency)

---

### 16. ShelfView.swift — Folder Cleanup
**File**: `Views/ShelfView.swift` (Lines 302, 314)

```swift
try? FileManager.default.removeItem(at: cleanupDirectory)
try? FileManager.default.removeItem(at: directory)
```

**Context**: Deleting result folders  
**Status**: Not critical (one-off user action)  
**Fix**: Can stay sync (low frequency, expected latency)

---

### 17. ModelManager.swift — Model Deletion
**File**: `Services/ModelManager.swift` (Lines 216, 223)

```swift
try? FileManager.default.removeItem(at: cacheURL)
try? FileManager.default.removeItem(at: modelsDirectoryURL)
```

**Context**: User deleting models  
**Frequency**: Rare user action  
**Status**: Can stay sync (expected latency for bulk operation)  
**Fix**: Optional async wrapper

---

### 18. BackgroundAssetsDownloadService.swift — Staging Cleanup
**File**: `Services/BackgroundAssetsDownloadService.swift` (Line 164)

```swift
try? FileManager.default.removeItem(at: stagingURL)
```

**Context**: Cleanup after model download  
**Status**: Background operation, acceptable  
**Fix**: Can stay sync

---

### 19. BundledModelService.swift — Staging Cleanup
**File**: `Services/BundledModelService.swift` (Line 92)

```swift
try? FileManager.default.removeItem(at: stagingURL)
```

**Context**: Cleanup after bundled model install  
**Status**: Background operation, acceptable  
**Fix**: Can stay sync

---

## 🟡 MEDIUM: Polling Patterns (Optimization Opportunity)

### 20. ConversionQueue.swift — Liveness Monitor
**File**: `Services/ConversionQueue.swift` (Line 334)

```swift
try? await Task.sleep(nanoseconds: 5_000_000_000)  // 5 second poll
```

**Context**: Checking for stalled jobs every 5 seconds  
**Status**: Already identified as #4 in PERFORMANCE_REVIEW  
**Frequency**: Continuous when conversions active  
**Fix**: Event-driven approach using notifications

---

### 21. ModelManager.swift — Progress Polling
**File**: `Services/ModelManager.swift` (Line 393)

```swift
try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms poll
```

**Context**: Polling progress file during model download  
**Status**: Already identified as #8 in PERFORMANCE_REVIEW  
**Frequency**: 2 polls/sec during downloads  
**Fix**: Use DispatchSourceFileSystemObject for file change events

---

### 22. WatchedFolderService.swift — Stability Delay
**File**: `Services/WatchedFolderService.swift` (Line 258, 341)

```swift
try? await Task.sleep(nanoseconds: 800_000_000)
try? await Task.sleep(nanoseconds: stabilityDelayNanoseconds)
```

**Context**: Waiting for files to stabilize before processing  
**Status**: By design (not a performance issue)  
**Fix**: Keep as-is (feature, not bug)

---

## 🟡 MEDIUM: Linear Searches (Should Be Indexed)

### 23. ConversionQueue.swift — Job Lookups
**File**: `Services/ConversionQueue.swift` (Lines 184, 227+)

```swift
guard let job = jobs.first(where: { $0.id == id }) else { return nil }
```

**Context**: Looking up job by UUID repeatedly  
**Frequency**: Once per progress update  
**Status**: Already identified as #5 in PERFORMANCE_REVIEW  
**Impact**: O(n) on each access  
**Fix**: Maintain UUID → index map

---

### 24. FirstPartyModelDownloadService.swift — Spec Lookup
**File**: `Services/FirstPartyModelDownloadService.swift` (Line 523)

```swift
guard let spec = specs.first(where: { $0.key == key }) else { ... }
```

**Context**: Finding model spec by key  
**Frequency**: Once per download  
**Status**: Low frequency, acceptable  
**Fix**: Optional; can stay sync

---

## 🟢 ACCEPTABLE (Already Good or Low Priority)

### 25. CLIConversionBroker.swift — Output Write
**File**: `Services/CLIConversionBroker.swift` (Line 165)

```swift
try data.write(to: url, options: .atomic)
```

**Context**: Writing CLI output  
**Status**: Expected latency for CLI  
**Fix**: N/A

---

### 26. MCPIntegrationService.swift — State Write
**File**: `Services/MCPIntegrationService.swift` (Line 186)

```swift
try encoder.encode(next).write(to: url, options: .atomic)
```

**Context**: Writing MCP server state  
**Status**: Background service, not user-facing  
**Fix**: N/A

---

## 📋 Prioritized Fix List

### Phase 1: Critical Blocking Operations (8 hours)
Use existing **FileWriteService** actor:

1. **SavePreference.swift** (3 writes) — ⚠️ User-facing save stall
2. **WatchedFolderService.swift** (2 writes) — ⚠️ Auto-conversion stall
3. **ConversionHistoryStore.swift** (1 write) — Medium priority
4. **PackCreditLedger.swift** (1 write) — Medium priority

**Work**: Change sync `write(to:)` calls to `await FileWriteService.shared.writeMarkdown()`

---

### Phase 2: File Metadata Consistency (6 hours)
Use **FileSizeReader** actor:

5. **FirstPartyModelDownloadService.swift** (1 location)
6. **NativeMetadataExtractor.swift** (1 location)

**Work**: Replace `resourceValues(forKeys: [.fileSizeKey])` with `await FileSizeReader.shared.readSize()`

---

### Phase 3: File Signature Caching (6 hours)
Create **FileSignatureReader** actor:

7. **WatchedFolderService.swift** (1 function: `fileSignature(for:folderID:)`)

**Work**: Extract signature checking into async actor with caching

---

### Phase 4: Event-Driven Polling (5 hours)
Replace sleep-based polling:

8. **ModelManager.swift** (progress polling) — Use DispatchSourceFileSystemObject
9. **ConversionQueue.swift** (liveness monitoring) — Use notifications or async streams

---

### Phase 5: Job Lookup Indexing (3 hours)
Optimize O(n) searches:

10. **ConversionQueue.swift** (UUID indexing) — Add UUID → index map

---

## Summary by File

| File | Issues | Priority | Effort |
|------|--------|----------|--------|
| SavePreference.swift | 3 writes | 🔴 P0 | 1.5h |
| WatchedFolderService.swift | 3 (2 writes, 1 signature) | 🔴 P0 | 2h |
| ConversionHistoryStore.swift | 1 write | 🟠 P1 | 0.5h |
| PackCreditLedger.swift | 1 write | 🟠 P1 | 0.5h |
| FirstPartyModelDownloadService.swift | 2 (1 size read, 1 enum) | 🟠 P1 | 1.5h |
| NativeMetadataExtractor.swift | 1 size read | 🟠 P1 | 0.5h |
| ModelManager.swift | 1 polling loop | 🟠 P1 | 2h |
| ConversionQueue.swift | 2 (1 polling, 1 indexing) | 🟠 P1 | 2h |
| MCPIntegrationService.swift | 1 pasteboard | 🟡 P2 | 0.5h |
| FileAccessService.swift | 3 pasteboard | 🟡 P2 | 1.5h |

**Total**: ~26 issues, ~12 hours of work, spread across 5 phases

---

## Implementation Approach

### Use Existing Services (Already Created)
- ✅ **FileWriteService** — for all .write() calls
- ✅ **FileSizeReader** — for resourceValues(forKeys: [.fileSizeKey])
- ✅ **DirectorySizeReader** — for enumerations

### Create New Services (Required)
- 🔨 **FileSignatureReader** — for WatchedFolderService caching
- 🔨 **JobIndexer** — for ConversionQueue O(1) lookups

### Infrastructure Changes
- 🔨 Replace polling with DispatchSourceFileSystemObject (ModelManager)
- 🔨 Add observation/notification mechanism (ConversionQueue liveness)

---

## Testing Strategy

After each phase:

1. **Build verification** — `xcodebuild build` (no errors)
2. **Unit tests** — `scripts/ci/gate.sh quick`
3. **Integration tests** — Manual testing for affected features
4. **Performance** — Instruments to verify no new blocking

**Checkpoint**: Run full gate after each 2-3 files modified

---

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| Breaking file persistence | Extensive testing of save paths |
| Losing async/await invariants | Keep MainActor boundaries clear |
| Introducing new races | Actor-based locking for shared state |
| Regression in existing features | Run full test suite per phase |

---

## Rollout Plan

1. **Phase 1-2** (next PR): File I/O standardization
2. **Phase 3** (PR after): File signature caching
3. **Phase 4** (PR after): Event-driven polling
4. **Phase 5** (final PR): Query optimization

Each PR focuses on one service family to minimize blast radius.

---

## Files to Create/Modify

### New Files (2)
1. `Services/FileSignatureReader.swift` (similar to FileSizeReader, ~70 lines)
2. `Services/JobIndexer.swift` (or extend ConversionQueue, ~40 lines)

### Modified Files (10)
1. `Services/SavePreference.swift` — Replace 3 writes
2. `Services/WatchedFolderService.swift` — Replace 3 operations
3. `Services/ConversionHistoryStore.swift` — Replace 1 write
4. `Services/PackCreditLedger.swift` — Replace 1 write
5. `Services/FirstPartyModelDownloadService.swift` — Replace 2 operations
6. `Services/NativeMetadataExtractor.swift` — Replace 1 read
7. `Services/ModelManager.swift` — Replace polling loop
8. `Services/ConversionQueue.swift` — Replace polling + add indexing
9. `Services/FileAccessService.swift` — Use FileWriteService
10. `Services/MCPIntegrationService.swift` — Optional pasteboard update

---

## Success Criteria

After completing all 5 phases:

✅ Zero blocking file I/O on main thread  
✅ All file operations use appropriate async patterns  
✅ All polling replaced with event-driven  
✅ All O(n) lookups optimized  
✅ Full test suite passes  
✅ App remains responsive during all operations
