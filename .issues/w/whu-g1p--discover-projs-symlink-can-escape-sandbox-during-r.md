---
# whu-g1p
title: 'discover_projs: symlink can escape sandbox during recursive scan'
status: completed
type: bug
priority: low
created_at: 2026-07-17T17:36:08Z
updated_at: 2026-07-17T17:38:29Z
sync:
    github:
        issue_number: "429"
        synced_at: "2026-07-17T17:39:29Z"
---

`DiscoverProjectsTool.search()` validates only the initial searchPath against the sandbox base. During recursion it descends into any real subdirectory via FileManager.fileExists/contentsOfDirectory (both follow symlinks) without re-checking each descended path against basePath. A symlink inside the tree pointing outside base lets the scan walk out of the sandbox and report .xcodeproj/.xcworkspace paths from there.

Severity: low — read-only, gated behind default sandbox, only leaks bundle path existence (no contents).

Analogous to getsentry/XcodeBuildMCP fix 46b2cf6 (#477), which added a per-entry isPathWithin boundary check in its recursive project-discovery walk. xc-mcp's exact prefix-match is NOT vulnerable (PathUtility.isPath(_:within:) is separator-aware), but the recursion lacks the per-entry re-check.

Fix: apply the existing PathUtility.isPath(_:within:) helper per descended entry (resolving symlinks) so entries whose real path falls outside basePath are skipped. Add a test with a symlink escaping the base.

- [x] Expose/reuse isPath(_:within:) boundary check
- [x] Re-validate each descended dir (real path) in search()
- [x] Test: symlink escaping base is skipped
- [x] Test: normal nested discovery still works

## Summary of Changes

Added `PathUtility.isWithinSandbox(_:)` (public) — resolves symlinks on both the candidate and base, then reuses the existing separator-aware `isPath(_:within:)`. Returns `true` when sandboxing is disabled, so `--no-sandbox` behavior is unchanged.

`DiscoverProjectsTool.search()` now guards each directory entry with `pathUtility.isWithinSandbox(fullPath)` before reporting or recursing, so a symlink resolving outside the base is skipped uniformly for workspaces, projects, and subdirectory recursion.

### Files
- `Sources/Core/Locators/PathUtility.swift` — new `isWithinSandbox(_:)`
- `Sources/Tools/Discovery/DiscoverProjectsTool.swift` — per-entry boundary guard
- `Tests/PathUtilityTests.swift` — `isWithinSandbox` accept/reject + sandbox-disabled tests
- `Tests/DiscoverProjectsSandboxTests.swift` — symlink-escape + normal-nesting E2E tests

### Verification
`swift_package_test` filter `PathUtilityTests|DiscoverProjectsSandboxTests` — 21 passed, 0 failed.
