---
# wxl-v16
title: Review tuist/xcodeproj 9.10.0–9.10.1 changes
status: completed
type: task
priority: normal
created_at: 2026-03-02T18:52:50Z
updated_at: 2026-03-02T19:02:23Z
sync:
    github:
        issue_number: "162"
        synced_at: "2026-03-02T19:11:15Z"
---

Upstream xcodeproj released 9.10.0 and 9.10.1. Review and act on relevant changes.

- [x] Review `dstSubfolder` addition in `PBXCopyFilesBuildPhase` (0af488c) — check if our copy-files tools need to expose the new subfolder destination option
- [x] Review `CommentedString.validString` perf optimization (2832e79) — free perf win
- [x] Consider bumping xcodeproj dependency from current pin to ≥9.10.1


## Summary of Changes

No changes needed — all three items were already addressed:

1. **Dependency bump**: Already at `from: "9.10.1"` (completed in jhp-0hl and k7v-xzm)
2. **dstSubfolder support**: Already integrated across 6+ tools — ListCopyFilesPhases reads both `dstSubfolderSpec` and `dstSubfolder`, ValidateProjectTool validates `dstSubfolder == .frameworks`, AddFrameworkTool/AddAppExtensionTool find embed phases by `dstSubfolder`, DuplicateTargetTool preserves it when copying. The old PBXProjWriter regex workaround for tuist/XcodeProj#1034 was removed.
3. **CommentedString.validString perf**: Pure internal optimization (15-20x faster serialization), no public API change. Already picked up via the dependency bump.
