---
# k8u-o2i
title: add_file creates duplicate file references and miscomputes paths relative to groups with path property
status: completed
type: bug
priority: high
created_at: 2026-03-01T19:27:58Z
updated_at: 2026-03-01T19:39:19Z
sync:
    github:
        issue_number: "159"
        synced_at: "2026-03-01T19:41:45Z"
---

## Context

Follow-up to 184-2cs (path doubling). The fix for that issue was marked completed, but files added via \`add_file\` to groups that have a \`path\` property still result in broken Xcode projects.

Discovered while building Swiftiomatic's Xcode project (\`Xcode/Swiftiomatic.xcodeproj\`) — the SwiftiomaticApp target has \`Models\` and \`Views\` subgroups under the \`SwiftiomaticApp\` group.

## Problem 1: Path doubling persists

**Group structure:**
\`\`\`
SwiftiomaticApp (name only, no path property)
├── Models (name = Models, path = Models)
│   └── AppModel.swift (path = SwiftiomaticApp/Models/AppModel.swift)
└── Views (name = Views, path = Views)
    └── AboutTab.swift (path = SwiftiomaticApp/Views/AboutTab.swift)
\`\`\`

**Problem:** The file reference paths are relative to the project root (\`SwiftiomaticApp/Models/AppModel.swift\`), but Xcode resolves them relative to the group's \`path\` property. So the resolved path becomes:

\`Views/\` (group path) + \`SwiftiomaticApp/Views/AboutTab.swift\` (file ref path) = \`Views/SwiftiomaticApp/Views/AboutTab.swift\` ❌

**Expected:** When a file is added to a group with \`path: Views\`, the file reference path should be relative to that group — e.g., just \`AboutTab.swift\`, or the group's path should not be set.

**Build error:**
\`\`\`
Build input files cannot be found:
  'Xcode/Views/SwiftiomaticApp/Views/AboutTab.swift'
  'Xcode/Models/SwiftiomaticApp/Models/AppModel.swift'
  ... (all 9 Model/View files)
\`\`\`

## Problem 2: Duplicate PBXFileReference entries

Each file added via \`add_file\` created 3-4 duplicate PBXFileReference entries with different UUIDs. For example, \`AppModel.swift\` has these refs in the pbxproj:

- \`965E14378C1964C4AF69D9E4\`
- \`A961AF4FDCFFD96D3EA03C0D\`
- \`E9DEA90B63C3B57E441054E3\`

Only one is used in the group's children list, but the others are orphaned entries. This happens for all 9 files (Models + Views), resulting in ~20 orphaned PBXFileReference entries.

## Reproduction

1. Create a project with a group hierarchy: \`SwiftiomaticApp\` (no path) → \`Views\` (path = Views)
2. Use \`add_file\` to add \`SwiftiomaticApp/Views/AboutTab.swift\` to the \`Views\` group in target \`SwiftiomaticApp\`
3. Observe: file reference has \`path = SwiftiomaticApp/Views/AboutTab.swift\` instead of \`AboutTab.swift\`
4. Observe: multiple PBXFileReference entries created for the same file

## Expected Fix

- When computing file reference paths, subtract the group's resolved path prefix from the file's absolute path
- Deduplicate: check for existing PBXFileReference with same resolved path before creating a new one

## Summary of Changes

### AddFileTool.swift
- **Deduplication**: Before creating a new PBXFileReference, checks if one already exists with the same resolved `fullPath`. Reuses existing refs and skips adding to the group if already present.
- **Path computation fix**: When a file is NOT under the group's resolved filesystem path (e.g., virtual groups with no `path` property), uses `sourceTree = .sourceRoot` with a path relative to the project root instead of `sourceTree = .group`. This prevents Xcode from prepending the group's path prefix, which caused path doubling. Files outside the project use `sourceTree = .absolute`.

### AddFileToolTests.swift
- Added `addFileOutsideGroupUsesSourceRoot`: reproduces the Swiftiomatic scenario (virtual parent group → subgroup with path) and verifies sourceRoot is used.
- Added `addFileNoDuplicateReferences`: calls add_file twice for the same file and verifies exactly 1 PBXFileReference exists.
