---
# 2ez-noo
title: Integrate Swift Backtrace API (SE-0419) for enhanced error diagnostics
status: completed
type: feature
priority: normal
created_at: 2026-03-07T22:02:18Z
updated_at: 2026-03-08T06:00:07Z
sync:
    github:
        issue_number: "184"
        synced_at: "2026-03-08T06:08:48Z"
---

## Context

SE-0419 Swift Backtrace API is available in Swift 6.2 toolchain via `import Runtime`, gated on **macOS 26.0+** deployment target. The `Runtime.swiftmodule` exists in `prebuilt-modules/26.2/` and compiles fine, but requires `libswiftRuntime.dylib` which only ships in the macOS 26 (Tahoe) OS image.

## Availability Strategy

Use `if #available(macOS 26.0, *)` to conditionally capture backtraces at runtime, keeping macOS 15 as the minimum deployment target. Gracefully absent on older systems.

## API Surface

```swift
import Runtime

let bt = try Backtrace.capture()           // raw frames
let sym = bt.symbolicated()                // with symbols + source locations
print(sym)                                 // human-readable output
```

Key types: `Backtrace`, `SymbolicatedBacktrace`, `Backtrace.Frame`, `Backtrace.Image`, `Backtrace.UnwindAlgorithm` (`.auto`, `.fast`, `.precise`).

Note: captures backtraces of the *current* process only — not applicable to debugged processes (LLDB `thread backtrace` remains necessary for that).

## Integration Points

- [x] `MCPErrorConvertible.asMCPError()` — attach backtrace to `MCPError.internalError` for unexpected failures
- [ ] Evaluate other error paths in Core runners where diagnostic context would help

## Constraints

- Not async-signal-safe — not for crash reporters
- macOS 26+ only at runtime
- xc-mcp minimum deployment target stays at macOS 15


## Summary of Changes

Added `import Runtime` and a `captureBacktrace()` helper to `MCPErrorConvertible.swift`. When an unexpected error (not `MCPError` or `MCPErrorConvertible`) hits `asMCPError()`, a symbolicated backtrace is appended to the error message on macOS 26+. On older systems, behavior is unchanged. No new dependencies — `Runtime` is a stdlib module gated behind `#available(macOS 26.0, *)`.
