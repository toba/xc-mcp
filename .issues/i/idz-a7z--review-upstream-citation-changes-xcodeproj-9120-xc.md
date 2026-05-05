---
# idz-a7z
title: Review upstream citation changes (XcodeProj 9.12.0, XcodeBuildMCP security fix)
status: completed
type: task
priority: normal
created_at: 2026-05-05T15:25:11Z
updated_at: 2026-05-05T15:40:11Z
sync:
    github:
        issue_number: "309"
        synced_at: "2026-05-05T15:41:11Z"
---

Two cited repos have HIGH-relevance commits to review:

## tuist/xcodeproj (main)
- `e5c356f` feat: support new Xcode 16 XCBuildConfiguration format (#1037)
- `fb79d68` [Release] XcodeProj 9.12.0
- `50c6cdc` chore(deps): update dependency tuist to v4.191.6 (#1125)

Touches `Sources/XcodeProj/Objects/Configuration/XCBuildConfiguration.swift`. All our project tools depend on XcodeProj — evaluate bumping the package dependency to 9.12.0 and verify nothing breaks with the new Xcode 16 XCBuildConfiguration format.

- [x] Review XCBuildConfiguration.swift diff
- [x] Bump XcodeProj to 9.12.0 in Package.swift
- [x] Run full test suite

## getsentry/XcodeBuildMCP (main)
- `38b57a7` feat: Workspace filesystem cleanup (#391)
- `e9780db` fix(security): close remaining /bin/sh -c shell-injection sites in bundle ID flows (#390)

The shell-injection fix touches `build_macos.ts` and `get_mac_bundle_id.ts`. Audit our analogous flows (MacOS/, Discovery bundle ID tools) for similar `/bin/sh -c` patterns.

- [x] Read XcodeBuildMCP PR #390 diff
- [x] Audit `Sources/Tools/MacOS/` and bundle-ID discovery tools for shell injection
- [x] Review workspace filesystem cleanup (#391) for ideas applicable to our session/derived-data handling


## Summary of Changes

**XcodeProj 9.10.1 → 9.12.0** (`Package.swift`). 9.12.0's `XCBuildConfiguration` diff is purely additive: a new initializer `init(name:baseConfigurationAnchor:baseConfigurationRelativePath:buildSettings:)` for xcconfigs that live inside a `PBXFileSystemSynchronizedRootGroup` (Xcode 16+). The existing `init(name:baseConfiguration:buildSettings:)` is unchanged — all 21 of our call sites across `CreateXcodeprojTool`, `AddTargetTool`, `DuplicateTargetTool`, `ScaffoldModuleTool`, scaffold tools, `PreviewCaptureTool`, and tests continue to compile. Build clean, full suite green (1100/0).

**Shell-injection audit — no findings.** XcodeBuildMCP PR #390 closed four `/bin/sh -c "defaults read ${appPath}/Info CFBundleIdentifier"` sites where `appPath` was interpolated into a shell string (CWE-78). xc-mcp doesn't have an analogous surface: `GetMacAppPathTool` (`Sources/Tools/MacOS/GetMacAppPathTool.swift:202`) and `GetMacBundleIdTool` (`Sources/Tools/Discovery/GetMacBundleIdTool.swift:163`) read Info.plist via in-process `PropertyListSerialization` — no subprocess, no shell. The only `/bin/sh` reference in the codebase is `DuplicateTargetTool.swift:153`, which copies a shell-script-build-phase's `shellPath` property into a duplicated phase — that's an Xcode project field, not a process invocation.

**Workspace filesystem cleanup (#391) — not applicable.** XcodeBuildMCP's cleanup targets its TypeScript daemon's per-workspace state directories. Our derived-data handling defers to `xcodebuild`'s built-in `-derivedDataPath` semantics and session state lives in-memory in `SessionManager`; no analogous cleanup work surfaced.

No changes needed beyond the dependency bump.
