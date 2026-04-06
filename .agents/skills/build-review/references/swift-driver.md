# Swift Driver — Build Pipeline

The [swift-driver](https://github.com/swiftlang/swift-driver) controls compilation scheduling.
Since Xcode 14, the integrated driver is embedded in the build system (no separate `swiftc`).

## Key Settings

- **SWIFT_USE_INTEGRATED_DRIVER**: `YES` (default). Setting `NO` causes `@response` file errors.
- **SWIFT_COMPILATION_MODE**:
  - `incremental` (Debug default) — compiles changed files; uses module dependency graph
  - `wholemodule` (Release default) — all files as one unit; no incremental artifacts
  - Neither mode affects `.debug.dylib` generation (that's `ENABLE_DEBUG_DYLIB`)
- **SWIFT_OPTIMIZATION_LEVEL**: `-Onone` (debug), `-O` (release), `-Osize`, `-Ounchecked`

## Incremental Build Internals

The driver maintains a module dependency graph tracking source → declaration deps, external
module deps, and build records. File hashing (SHA256, Swift 6.1+, PR #1923) prevents
unnecessary recompilation when timestamps change but content doesn't.

## For Injected Targets

- `wholemodule` — avoids incremental dependency graph issues and cross-file symbol problems
- `-Onone` — keeps debug info, avoids compiler crashes on preview-stripped code
- The driver has **no flags to suppress `.debug.dylib`** — that's the build system, not the compiler

## Sources

- [swiftlang/swift-driver](https://github.com/swiftlang/swift-driver)
- [PR #1923: File hashing](https://github.com/swiftlang/swift-driver/pull/1923)
