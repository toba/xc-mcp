---
# k7v-xzm
title: Bump XcodeProj dependency to 9.10.1
status: completed
type: task
priority: normal
created_at: 2026-03-01T18:06:21Z
updated_at: 2026-03-01T18:07:14Z
sync:
    github:
        issue_number: "152"
        synced_at: "2026-03-01T18:14:00Z"
---

Bump XcodeProj from ≥9.7.2 to ≥9.10.1 in Package.swift.

Gains:
- Xcode 26 `dstSubfolder` support in `PBXCopyFilesBuildPhase` (0af488c)
- Perf optimization in `CommentedString.validString` (2832e79)

## TODO

- [x] Update Package.swift version constraint
- [x] Run `swift package resolve`
- [x] Run full test suite to verify no regressions
- [x] Check if any project tools need updates for the new `dstSubfolder` property


## Summary of Changes

No changes needed — the dependency was already at 9.10.1 in both `Package.swift` (constraint `from: "9.10.1"`) and `Package.resolved` (revision `01bb770`). The codebase already uses the `dstSubfolder` property throughout project tools, and `PBXProjWriter.swift` documents XcodeProj 9.10.0+ native support.
