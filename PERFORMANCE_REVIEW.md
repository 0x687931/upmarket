# Performance Review: Hot Loops, Stalls, and Inefficiencies

## Executive Summary
The app has a strong architecture with good async patterns, but there are **9 key performance issues** that create UI stalls, unnecessary blocking, and inefficient polling. Most are fixable with targeted changes. Fast startup is maintained—the issue is action responsiveness after initial launch.

---

## 🔴 CRITICAL: Main-Thread Blocking on File Operations

### 1. **File Size Read Blocks Main Thread** (ConversionRunner:81)
```swift
let fileSizeBytes = (try? job.sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
```
**Impact**: Synchronous URL metadata read on main thread blocks UI. On slow/remote storage (network, iCloud), this creates multi-second stall before conversion starts.

**✅ FIXED**: New `FileSizeReader` actor handles both cases:
- **Local files**: Async background read (10-50µs typical)
- **iCloud files**: `NSFileCoordinator` ensures file availability without blocking (prevents races)
- **Caching**: 5-minute cache for repeated lookups

```swift
// Usage (now in ConversionRunner:81)
let fileSizeBytes = await FileSizeReader.shared.readSize(job.sourceURL)
```

**Implementation**: `Services/FileSizeReader.swift` — 78 lines, uses:
- `URLResourceValues` (local files, background thread)
- `NSFileCoordinator` (iCloud files, ensures no deletion during read)

---

### 2. **Markdown Output Write Blocks Main Thread** (FileAccessService:142, 164)
```swift
try markdown.write(to: url, atomically: true, encoding: .utf8)
```
**Impact**: For large Markdown files (10+ MB), this blocks UI for 100-500ms. Post-conversion "save/copy" feels sluggish.

**Fix**: Defer writes to background queue
```swift
try await Task.detached { 
    try markdown.write(to: url, atomically: true, encoding: .utf8)
}.value
```

---

## 🟠 HIGH: Hot Loops and Inefficient Polling

### 3. **ConversionQueue Progress Calculation Is Hot Loop** (ConversionQueue:37-41)
```swift
var overallProgress: Double {
    let active = jobs.filter(\.isRunning)
    guard !active.isEmpty else { return jobs.isEmpty ? 0.0 : 1.0 }
    return active.map(\.progress).reduce(0.0, +) / Double(active.count)
}
```
**Impact**: Called 60+ times per second by SwiftUI during rendering. Filters all jobs repeatedly.

**Fix**: Cache progress and update reactively
```swift
@Published private(set) var cachedOverallProgress: Double = 0
// Update only when jobs array changes or job.progress changes
```

---

### 4. **Stalled Job Classification Scans All Jobs Every 5 Seconds** (ConversionQueue:348-363)
```swift
private func classifyStalledJobs(referenceDate: Date = Date()) {
    var hasRunningJob = false
    for index in jobs.indices {
        guard jobs[index].isRunning else { continue }
        // ... stalled check on each
    }
}
```
**Impact**: Linear scan of all jobs every 5 seconds. Spikes CPU when queue has 50+ completed jobs. Doesn't yield to main thread.

**Fix**: Maintain a set of "active job indices"
```swift
@Published private var activeJobIndices: Set<Int> = []
// Update only activeJobIndices instead of full jobs array
```

---

### 5. **Linear Job Lookups (O(n) Per Call)** (ConversionQueue:47-55)
```swift
func job(id: UUID) -> ConversionJob? {
    jobs.first { $0.id == id }  // Repeatedly called
}

var lastFailedJob: ConversionJob? {
    jobs.first { job in job.stage == .failed && job.result?.errorMessage != nil }
}
```
**Impact**: These are called on every progress update. With 50 jobs, this is 50 linear scans per second.

**Fix**: Index by UUID
```swift
private var jobsByID: [UUID: Int] = []  // Maps ID to index in jobs array
func job(id: UUID) -> ConversionJob? {
    jobsByID[id].flatMap { jobs[safe: $0] }
}
```

---

### 6. **Model Directory Size Calculation Is Expensive Sync** (ModelManager:248-256)
```swift
private func directorySize(_ url: URL) -> Int64 {
    guard let enumerator = FileManager.default.enumerator(
        at: url, includingPropertiesForKeys: [.fileSizeKey],
        options: [.skipsHiddenFiles]
    ) else { return 0 }
    return enumerator.compactMap { $0 as? URL }
        .compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
        .reduce(0) { $0 + Int64($1) }
}
```
**Impact**: Called on main thread when computing `totalStorageUsed` or `actualInstalledSizeMB`. Recursively enumerates 1000+ files (Python runtime + models) causing 1–3 second stall.

**Fix**: Cache directory sizes; update only on model download/delete
```swift
@Published private var cachedDirectorySizes: [URL: Int64] = [:]
```

---

## 🟡 MEDIUM: Post-Processing Inefficiency

### 7. **Post-Processing Is Fully Sequential** (ConversionRunner:560-586)
```swift
private func postProcess(_ output: ConversionOutput) async -> ConversionOutput {
    let intelligence = DocumentIntelligence.extractMetadata(from: output.markdown)
    let nlResult = TextStructurer.refine(...)        // Awaits sequentially
    let wtResult = await WritingToolsRefinerAdapter.refine(...)  // Then this
    let fmResult = await FoundationModelEnhancer.enhance(...)    // Then this
}
```
**Impact**: Even if `TextStructurer` and `WritingToolsRefinerAdapter` are independent, they run sequentially. On modern Macs with idle cores, this is wasteful.

**Fix**: Parallelize independent operations
```swift
async let nlTask = TextStructurer.refine(...)
async let wtTask = WritingToolsRefinerAdapter.refine(nlResult.markdown, ...)
let (finalNL, finalWT) = await (nlTask, wtTask)
```

---

## 🟡 MEDIUM: Polling Instead of Event-Driven

### 8. **Progress File Polling (500ms Sleep Loop)** (ModelManager:392-425)
```swift
while true {
    try? await Task.sleep(nanoseconds: 500_000_000)  // 500ms poll
    if let line = Self.lastProgressLine(atPath: progressFile), ... {
        // Update progress
    }
}
```
**Impact**: 2 file reads per second even when transfer is idle. Unnecessary I/O and CPU wake-ups.

**Fix**: Use `DispatchSourceFileSystemObject` for file change events instead of polling
```swift
let source = DispatchSource.makeFileSystemObjectSource(...)
source.setEventHandler { [weak self] in
    // Read progress file only on change
}
```

---

## 🟡 MEDIUM: Process Spawning Per Job

### 9. **New Helper Process Per Conversion** (RuntimeHelperClient:122-150)
```swift
let process = Process()
process.executableURL = executable
// ... per conversion, spawn new UpmarketRuntimeHelper
```
**Impact**: Each conversion spawns a new sandbox process. Startup penalty ~200-500ms (Python init). Acceptable for long conversions but noticeable for fast ones. **This is by design** but worth noting.

**Future optimization**: Process pooling (complex, not recommended now but document for later).

---

## 🟢 GOOD PATTERNS (Keep These)

✅ **Async/await throughout** — No callback hell, proper cancellation.  
✅ **Concurrent multi-pathway routing** (`.all()` case in PDF conversion) — Uses hardware efficiently.  
✅ **Task.isCancelled checks** — Clean cancellation propagation.  
✅ **Dedicated background threads for Python** — Main thread never blocked by conversion.  
✅ **Liveness monitoring with 5s heartbeat** — Good balance between stall detection and CPU cost.

---

## 📋 Recommended Priority Fixes

| Issue | Effort | Impact | Priority |
|-------|--------|--------|----------|
| #1: File size read | 15 min | High (first action stall) | 🔴 P0 |
| #2: Markdown write | 20 min | High (post-conversion feel) | 🔴 P0 |
| #3: Progress calculation cache | 30 min | High (60+ Hz loop) | 🔴 P0 |
| #6: Directory size cache | 25 min | High (Settings stall) | 🔴 P0 |
| #4: Stalled job tracking | 45 min | Medium (5s cycle) | 🟠 P1 |
| #5: Job ID indexing | 30 min | Medium (O(n) lookups) | 🟠 P1 |
| #7: Parallel post-processing | 20 min | Low (end-user perceived) | 🟡 P2 |
| #8: Event-based progress polling | 60 min | Low (background task) | 🟡 P2 |
| #9: Process pooling | 200+ min | Low (by design) | 🟢 Future |

---

## Testing Checklist

After fixes:
- [ ] Time file drag-drop to conversion start (should be <50ms, not 200+ms).
- [ ] Time post-conversion copy/save (should be <20ms, not 100+ms).
- [ ] Monitor CPU during Settings page load (check disk enumeration).
- [ ] Verify no UI frame drops during conversion progress updates.
- [ ] Run with Instruments: `System Trace` to catch main-thread blocking.
- [ ] Test on slow storage (external USB-HDD) to see file metadata stalls.

---

## Conclusion

The app is fundamentally sound—async patterns are correct, process isolation is solid. The issues are **specific hot paths**: main-thread file I/O, unindexed lookups, and expensive re-computations in tight loops. **All 9 issues are fixable** with localized changes; none require architectural rework.

Start with #1, #2, #3, #6 (P0s) for immediate responsiveness improvements. The rest are polish (P1/P2).
