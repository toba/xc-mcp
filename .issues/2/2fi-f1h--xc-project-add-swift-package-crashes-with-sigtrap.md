---
# 2fi-f1h
title: 'xc-project: add_swift_package crashes with SIGTRAP (exit code -5)'
status: completed
type: bug
priority: high
created_at: 2026-03-26T02:23:33Z
updated_at: 2026-03-26T03:11:54Z
sync:
    github:
        issue_number: "242"
        synced_at: "2026-03-26T03:14:28Z"
---

## Reproduction

\`add_swift_package\` crashes the xc-project MCP server process with exit code -5 (SIGTRAP).

**Steps:**
1. Start xc-project server: `/opt/homebrew/bin/xc-project --no-sandbox`
2. Initialize JSON-RPC session (works)
3. Call `list_swift_packages` (works fine)
4. Call `add_swift_package` with valid arguments → server crashes

**Arguments used:**
```json
{
  "project_path": "Thesis.xcodeproj",
  "package_url": "https://github.com/pointfreeco/swift-dependencies",
  "requirement": "from: 1.8.1",
  "product_name": "Dependencies",
  "target_name": "Core"
}
```

**Observed behavior:**
- `list_swift_packages` returns successfully
- `add_swift_package` produces no JSON-RPC response, no stderr output
- Process exits with code -5 (SIGTRAP — Swift fatal error / assertion)
- When called from Claude Code, the connection closes and the xc-project MCP server becomes unavailable for the rest of the session

**Expected:** Server should either succeed or return a JSON-RPC error response.

**Workaround:** Add the SPM package manually in Xcode or by editing the pbxproj directly.

## Environment

- xc-project 1.0.0 (`/opt/homebrew/bin/xc-project`)
- macOS 26, Xcode 26.2.0
- Target project: Thesis.xcodeproj (5 existing SPM packages, local macro package)


## Root Cause

Upstream bug in XcodeProj's `PBXProjEncoder.sortProjectReferences(for:outputSettings:)` at line 491: it force-unwraps `PBXFileElement.name` which is nil when a project reference's file element only has `path` set (e.g. a self-referencing `Thesis.xcodeproj` entry).

The crash only manifests in release builds because debug builds don't inline the force-unwrap into a silent trap — they print the error message instead.

## Fix

Added a workaround in `PBXProjWriter.write()` that backfills `name` from `path` on any ProjectRef file element with a nil `name` before delegating to XcodeProj's write.

## Summary of Changes

- `Sources/Tools/Project/PBXProjWriter.swift` — backfill nil `name` from `path` on project reference file elements before writing
- `Tests/AddSwiftPackageToolTests.swift` — added regression test `Write project with nameless project reference` and test for projects with existing packages
