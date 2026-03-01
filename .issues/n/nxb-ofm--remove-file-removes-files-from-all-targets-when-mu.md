---
# nxb-ofm
title: remove_file removes files from all targets when multiple targets have files with the same name
status: completed
type: bug
priority: high
created_at: 2026-03-01T18:33:08Z
updated_at: 2026-03-01T18:36:59Z
sync:
    github:
        issue_number: "156"
        synced_at: "2026-03-01T18:44:48Z"
---

## Bug

When \`remove_file\` is called to remove a file from the project, it removes **all** file references with that filename across **all** targets, even when the files are at different paths and belong to different targets.

### Reproduction

1. Two targets each have their own \`SharedDefaults.swift\`:
   - \`SwiftiomaticExtension/SharedDefaults.swift\` → target SwiftiomaticExtension
   - \`SwiftiomaticApp/Models/SharedDefaults.swift\` → target SwiftiomaticApp

2. Call:
   \`\`\`
   remove_file(file_path: "SwiftiomaticApp/Models/SharedDefaults.swift")
   \`\`\`

3. Result: \`"Successfully removed SharedDefaults.swift from project. Removed from targets: SwiftiomaticExtension, SwiftiomaticApp"\`

Both files are removed, not just the one at the specified path.

### Root Cause

The tool appears to match by **filename** rather than by **full path** when finding \`PBXFileReference\` entries to remove. Two files with the same name but different paths and different target memberships are treated as the same file.

### Expected Behavior

\`remove_file\` should match on the **full path** (relative to project root), not just the filename. Only the file reference at the exact specified path should be removed. Other files with the same name in different groups/targets should be untouched.

### Impact

This makes it impossible to safely remove a file when another target has a file with the same name — the other target's file reference is silently destroyed, requiring manual re-addition.

### Affected Files

- Likely in \`Sources/Tools/Project/RemoveFileTool.swift\` — file lookup logic

## Summary of Changes

**Root cause**: `RemoveFileTool` matched file references by filename (`fileRef.name == fileName || fileRef.path == fileName`) in addition to path, causing all files with the same name across different targets to be removed.

**Fix**: Replaced filename-based matching with `fullPath(sourceRoot:)` resolution. A new `matchesRequestedFile()` helper computes each `PBXFileReference`'s absolute path via the XcodeProj API and compares it against the resolved file path. This ensures only the file at the exact requested path is removed.

**Files changed**:
- `Sources/Tools/Project/RemoveFileTool.swift` — replaced matching logic
- `Tests/RemoveFileToolTests.swift` — added regression test with two targets having same-named files
