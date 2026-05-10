---
# ibk-gjo
title: 'clean(derived_data: true) cleans the wrong DerivedData when xc-mcp uses its own build directory'
status: completed
type: bug
priority: high
created_at: 2026-05-10T03:05:17Z
updated_at: 2026-05-10T03:08:50Z
sync:
    github:
        issue_number: "320"
        synced_at: "2026-05-10T03:11:04Z"
---

## Symptom

When editing a macro plugin's source files (e.g. `Core/Macros/Sources/.../TableMacro+ExtensionMacro.swift`), subsequent `build_macos` / `test_macos` calls report success but the macro expansions in dependent targets are stale — the new plugin code is compiled but consumers keep using the previously-cached expansion output. `clean(derived_data: true)` returns a successful message but does not fix it.

## Root cause

`mcp__xc-build__clean(derived_data: true)` deletes `~/Library/Developer/Xcode/DerivedData/<Project>-<hash1>/`, but xc-mcp's build commands are run with `-derivedDataPath ~/Library/Caches/xc-mcp/DerivedData/<Project>-<hash2>/` (or similar). The hashes are different — the standard Xcode DerivedData is cleared but xc-mcp's own DerivedData is not, so subsequent `build_macos` invocations reuse the stale macro expansion artifacts in the xc-mcp cache.

In the session that surfaced this, the relevant paths were:
- Cleared by `clean(derived_data: true)`: `~/Library/Developer/Xcode/DerivedData/Thesis-ddfqsiuxmcpnzhcbomdlbbstfbci/`
- Actually used by the build: `~/Library/Caches/xc-mcp/DerivedData/Thesis-4019ecb6511d/`

The fix that worked was a manual `rm -rf ~/Library/Caches/xc-mcp/DerivedData/Thesis-4019ecb6511d/`, after which the next build picked up the new macro behavior immediately.

## Fix options (any of these would have helped)

- [x] **Primary:** `clean(derived_data: true)` now clears xc-mcp's scoped DerivedData (the path actually passed to `-derivedDataPath`) in addition to matching entries in the standard Xcode DerivedData location.
- [ ] Detect macro-plugin-source edits since last build and force clean of dependent target build products. Heuristic: any `*.swift` newer than the macro plugin binary product whose path matches `*/Macros/Sources/**` or sits inside an SPM package whose `Package.swift` declares a `.macro(name:)` target.
- [ ] Add an explicit `clean_macros` parameter to `build_macos` / `test_macos` that wipes macro plugin build products and dependents before building, or a new `clean(macro_consumers: true)` flag.
- [ ] Surface a diagnostic when the macro plugin binary is older than its source files: `build_macos` should warn when this skew is detected because Xcode's incremental tracking is known to miss this case.
- [ ] Document this footgun prominently in the README / tool descriptions: 'When modifying macro plugins, prefer `clean(derived_data: true)` followed by a fresh build; xcodebuild's incremental cache does not reliably re-expand consumers on plugin-only changes.'

## Repro

1. In any project with a macro plugin (e.g. `thesis`), edit a behavior-affecting line in the plugin (change a default, flip a condition).
2. Run `build_macos` — succeeds.
3. Run a test that depends on the changed behavior — observes old behavior.
4. Run `clean(derived_data: true)` — succeeds.
5. Re-run the test — still old behavior.
6. `rm -rf ~/Library/Caches/xc-mcp/DerivedData/<project>-*/`.
7. Re-run the test — new behavior, finally.

## Why this matters

Macro debugging loops are already painful (the plugin is a separate target, runs at compile time, can't be `print`-debugged from outside). Having `clean(derived_data: true)` silently target the wrong directory turns a 30-second iteration into a 30-minute hunt for which cache to nuke. In the session this came from, I spent ~10 minutes verifying my macro change was correct, instrumenting it with a debug flag, and rebuilding repeatedly before realizing the canonical 'Xcode' DerivedData path being cleaned was not the path xc-mcp's commands were using.


## Summary of Changes

- `Sources/Tools/Utility/CleanTool.swift`: rewrote `cleanDerivedDataDirectory` to first delete the scoped path returned by `DerivedDataScoper.effectivePath(workspacePath:projectPath:)` (i.e. `~/Library/Caches/xc-mcp/DerivedData/<Project>-<hash>` or whatever override is in effect via `XC_MCP_DERIVED_DATA_PATH` / `XC_MCP_DISABLE_DERIVED_DATA_SCOPING`), then continue cleaning matching entries under `~/Library/Developer/Xcode/DerivedData/` so users who also build via Xcode get both caches wiped. Extracted a `removePath` helper that retains the existing FileManager → `rm -rf` fallback for permission edge cases. Reports both deleted paths and per-path failures instead of bailing on the first error.
- Updated the `derived_data` parameter description to document the new dual-location behavior so callers know what gets removed.

The other fix options enumerated in the bug (macro-edit heuristic, `clean_macros` flag, plugin-skew warning, README docs) are not implemented — the primary fix addresses the reported symptom; the rest can be follow-ups if the issue recurs after this change.
