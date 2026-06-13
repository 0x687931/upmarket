# Threading Model

Upmarket uses Swift's structured concurrency (async/await) with clear actor boundaries to prevent data races and ensure deterministic behavior.

## Overview

- **UI Updates:** @MainActor enforces all SwiftUI state changes on the main thread.
- **Background Work:** File I/O, conversions, and metrics run on concurrent background threads via Task/async.
- **Actors:** Services that manage shared mutable state (like `FileSystemMetrics`) use actor isolation.

## Key Components

### Main Thread (@MainActor)

The following are explicitly isolated to the main thread:

- `AppDelegate` — app lifecycle and window management
- `MenuBarStatusController` — menu bar icon updates
- `ConversionQueue` — job state mutations and publishing state changes to SwiftUI views
- `StoreManager` — purchase state and entitlements (ObservableObject)

**Why?** SwiftUI state changes must happen on the main thread. These services publish state that SwiftUI views observe, so isolation to @MainActor ensures consistency.

Example from `AppDelegate`:

```swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // This method runs on the main thread at app startup
    }
}
```

### Background Threads (async)

The following run on background threads and use async/await:

- `ConversionRunner` — conversion orchestration (async, runs off main thread)
- `FileSystemMetrics` — file I/O via actor isolation
- `RuntimeHelperClient` — subprocess communication (IPC, blocking but off main thread)
- `PythonWorker` — Python subprocess invocation (async)
- `WritingToolsService` — Writing Tools refinement (async, macOS 15.1+)
- `FoundationModelEnhancer` — foundation model calls (async)

**Why?** These perform blocking or long-running work (disk I/O, subprocess communication, model inference). Running them off the main thread prevents UI freezes.

Example from `ConversionRunner`:

```swift
func run(_ job: ConversionJob) async -> ConversionResult {
    // This is async and runs off the main thread
    // UI updates are posted back to @MainActor services via notifications
}
```

### Actors (Isolated Mutable State)

Shared mutable state uses actor isolation:

```swift
actor FileSystemMetrics {
    private var sizeCache: [URL: CacheEntry] = [:]  // Isolated
    
    func readFileSize(_ url: URL) async -> Int64 {
        // Mutations to sizeCache are serialized through the actor
    }
}
```

**Why?** Actors prevent concurrent access to mutable state without explicit synchronization. All mutations are serialized, preventing race conditions.

### UI → Background → UI Flow

Typical conversion flow:

1. **User clicks "Convert"** on SwiftUI view (main thread)
2. **View calls `ConversionQueue.add()`** → state change on @MainActor (main thread)
3. **`ConversionQueue` spawns task** → `ConversionRunner.run()` (background thread, async)
4. **`ConversionRunner` does file I/O, Python calls, etc.** (background)
5. **`ConversionRunner` publishes result** → posts `Notification` (any thread)
6. **`ConversionQueue` receives notification** → `@MainActor` context resumes (main thread)
7. **SwiftUI view observes state change** and re-renders (main thread)

## Preventing Data Races

### ✅ Safe Patterns

```swift
// Safe: @MainActor state change
@MainActor
func updateUI() {
    self.isLoading = false
}

// Safe: actor isolation
actor MyService {
    func mutateState() async {
        self.state = newValue  // Serialized through actor
    }
}

// Safe: closure capture in async task
Task {
    let snapshot = self.state  // Capture on main thread first
    let result = await doWork(with: snapshot)  // Pass snapshot to background
    // result cannot hold references to self's mutable state
}
```

### ❌ Unsafe Patterns (Will Not Compile or Will Cause Runtime Issues)

```swift
// ❌ Unsafe: updating @MainActor state from background
Task {
    self.isLoading = true  // Error: cannot access @MainActor from background
}

// ❌ Unsafe: holding mutable actor state across await
let cache = actor.cache
await someAsync()
cache.mutate()  // Error: actor isolation prevents this
```

## Testing with Concurrency

Tests in `UpmarketTests` use `@MainActor` for XCTestCase subclasses:

```swift
@MainActor
final class ConversionQueueTests: XCTestCase {
    func testQueueState() async {
        let queue = ConversionQueue.shared
        queue.add(job)  // Safe: @MainActor
        await queue.cancel(job)  // Safe: async on @MainActor
    }
}
```

## Performance Implications

- **Main Thread:** Kept free for UI rendering. UI freezes are user-visible.
- **Background Threads:** File I/O and conversions run off main thread (good for responsiveness).
- **Actor Overhead:** Minimal; serialization cost is negligible for file system operations.

## Debugging Tips

If you see:
- `'X' is only available in macOS A or newer` — wrap in `@available` or conditional `#if`
- `cannot access 'x' from outside of the actor` — either `await` it on the actor, or call it with explicit actor context
- `main actor-isolated 'X' cannot be called from background context` — call it from `@MainActor` context or dispatch to main thread

Use Instruments → System Trace to verify your app doesn't block the main thread during conversions.
