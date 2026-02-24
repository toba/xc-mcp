---
# wsv-fd4
title: Migrate from Foundation Process to swift-subprocess
status: completed
type: feature
priority: normal
created_at: 2026-02-22T19:12:44Z
updated_at: 2026-02-22T19:50:31Z
sync:
    github:
        issue_number: "101"
        synced_at: "2026-02-24T18:57:43Z"
---

## Context

The pipe deadlock fix (lcu-gfr) added `ProcessResult.drainPipes(stdout:stderr:)` using `DispatchQueue.global().async` + `DispatchSemaphore` + `nonisolated(unsafe)` to read stdout/stderr concurrently before `waitUntilExit()`. This is correct and follows Apple DTS-endorsed patterns, but it's manual plumbing that `Subprocess` (SF-0007) handles internally.

## Proposal

Replace `Foundation.Process` usage with [swift-subprocess](https://github.com/swiftlang/swift-subprocess) across all runners. `Subprocess` is the officially blessed async replacement for `Process` that eliminates manual pipe management entirely.

```swift
import Subprocess
let result = try await run(
    .name("xcodebuild"),
    arguments: ["build"],
    output: .data(limit: 10_485_760),
    error: .data(limit: 10_485_760)
)
```

## Requirements

- Swift 6.1+ (package is available standalone; will be in Foundation proper later)
- All callers must be async (Subprocess is async-only by design)

## Scope

Files that currently manage Process + pipes manually:

| File | Pattern |
|------|---------|
| `Sources/Core/ProcessResult.swift` | `drainPipes()` + `run()` — central helper |
| `Sources/Core/SimctlRunner.swift` | `withCheckedThrowingContinuation` + Process |
| `Sources/Core/DeviceCtlRunner.swift` | same |
| `Sources/Core/SwiftRunner.swift` | same |
| `Sources/Core/XctraceRunner.swift` | same |
| `Sources/Core/XcodeStateReader.swift` | sync Process usage |
| `Sources/Core/XCResultParser.swift` | standalone Process for xcresulttool |
| `Sources/Core/LLDBRunner.swift` | Process for pkill/open + long-running LLDB sessions |
| `Sources/Tools/Debug/BuildDebugMacOSTool.swift` | otool, codesign, extract |
| `Sources/Tools/Simulator/PreviewCaptureTool.swift` | pgrep, codesign, pkill |

## Migration notes

- `ProcessResult.run()` is sync — callers like `FileUtility.readTailLines` and `DoctorTool` would need to become async
- The `withCheckedThrowingContinuation` wrappers in runners become unnecessary since Subprocess is natively async
- Long-running processes (LLDBRunner sessions, xctrace recording) need `Subprocess`'s streaming APIs rather than `.data()` collection
- `drainPipes()` can be deleted entirely after migration
- Fire-and-forget calls (pkill, codesign --sign) may use `.discard` for output

## Research sources

- [Apple Developer Forums: Process() return values (Quinn's pattern)](https://developer.apple.com/forums/thread/129752)
- [SF-0007 Subprocess proposal](https://github.com/swiftlang/swift-foundation/blob/main/Proposals/0007-swift-subprocess.md)
- [SF-0007 3rd review (pipe deadlock discussion)](https://forums.swift.org/t/review-3rd-sf-0007-subprocess/78078)
- [swift-subprocess GitHub](https://github.com/swiftlang/swift-subprocess)
- [Michael Tsai: Swift 6.2 Subprocess](https://mjtsai.com/blog/2025/10/30/swift-6-2-subprocess/)
- [Saagar Jha: Swift Concurrency Waits for No One](https://saagarjha.com/blog/2023/12/22/swift-concurrency-waits-for-no-one/)
- [Swift Forums: Cooperative pool deadlock](https://forums.swift.org/t/cooperative-pool-deadlock-when-calling-into-an-opaque-subsystem/70685)
- [Swift Forums: NSPipe readabilityHandler + Swift 6](https://forums.swift.org/t/swift-6-concurrency-nspipe-readability-handlers/59834)


## Summary of Changes

Migrated all eligible `Foundation.Process()` call sites to [swift-subprocess](https://github.com/swiftlang/swift-subprocess) (SF-0007).

### What changed
- Added `swift-subprocess` 0.3.0 dependency to `XCMCPCore` and `XCMCPTools` targets
- Added `ProcessResult.runSubprocess()` bridge method that wraps `Subprocess.run()` and returns the existing `ProcessResult` type
- Converted `ProcessResult.run()` from sync to async (delegates to `runSubprocess()`)
- Deleted `ProcessResult.drainPipes()` — no longer needed
- Migrated 4 async runners: `SimctlRunner`, `DeviceCtlRunner`, `SwiftRunner`, `XctraceRunner`
- Migrated 3 sync helpers to async: `XCResultParser`, `XcodeStateReader`, `CoverageParser`
- Migrated `XcodebuildRunner` streaming from `readabilityHandler` + polling to `Subprocess` streaming closure + `TaskGroup`
- Migrated 5 Process() calls in `BuildDebugMacOSTool` (otool, install_name_tool, codesign)
- Migrated 4 Process() calls in `PreviewCaptureTool` (codesign, pgrep, pkill)
- Migrated all remaining `ProcessResult.run()` callers to async (stop tools, open tools, launch tools, DoctorTool)

### Excluded (per plan)
- `LLDBRunner` (PTY requirement)
- Long-running processes: `SimctlRunner.recordVideo`, `XctraceRunner.record`, log capture start tools
- `PreviewCaptureTool` macOS app launch (needs `Process` for environment variable injection + lifecycle control)
- `IntegrationTestHelper` (sync static initializer context)

### Verification
- `swift build` — clean
- `swift test` — 538/538 passed
- `swiftformat . && swiftlint` — clean (no new warnings)
