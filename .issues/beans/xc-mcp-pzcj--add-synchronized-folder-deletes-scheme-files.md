---
# xc-mcp-pzcj
title: add_synchronized_folder deletes scheme files
status: completed
type: bug
priority: critical
created_at: 2026-01-26T22:19:25Z
updated_at: 2026-01-27T00:33:43Z
---

## Summary

When using `add_synchronized_folder` (and likely other project-modifying operations), the xc-project MCP server deletes scheme files from the project.

## Reproduction Steps

1. Start with a project that has schemes in `*.xcodeproj/xcshareddata/xcschemes/`
2. Call `add_synchronized_folder` to add a new synchronized folder
3. Observe that scheme files are deleted

## Observed Behavior

After calling:
```
add_synchronized_folder(
  project_path: "Thesis.xcodeproj",
  folder_path: "Core/Sources",
  target_name: "Core"
)
```

The following scheme files were deleted:
- `Thesis.xcodeproj/xcshareddata/xcschemes/Standard.xcscheme`
- `Thesis.xcodeproj/xcshareddata/xcschemes/Old Standard.xcscheme`

And these were modified (possibly corrupted):
- `Administration.xcscheme`
- `CI.xcscheme`
- `Documentation.xcscheme`
- `Unused Code.xcscheme`

Git status showed:
```
modified:   Thesis.xcodeproj/xcshareddata/xcschemes/Administration.xcscheme
modified:   Thesis.xcodeproj/xcshareddata/xcschemes/CI.xcscheme
modified:   Thesis.xcodeproj/xcshareddata/xcschemes/Documentation.xcscheme
deleted:    Thesis.xcodeproj/xcshareddata/xcschemes/Old Standard.xcscheme
deleted:    Thesis.xcodeproj/xcshareddata/xcschemes/Standard.xcscheme
modified:   Thesis.xcodeproj/xcshareddata/xcschemes/Unused Code.xcscheme
```

## Expected Behavior

Project modifications should only affect `project.pbxproj`, not scheme files. Schemes should be preserved.

## Technical Context

- The Thesis project uses XCBuildCore's `PBXProj` for project manipulation
- Schemes are stored in `xcshareddata/xcschemes/` directory
- The scheme deletion occurs even when only `project.pbxproj` should be modified
- Reverting `project.pbxproj` alone is NOT sufficient - scheme files must be restored separately

## Impact

- **Critical**: Users lose their build schemes after any project modification
- Schemes contain build settings, test configurations, environment variables
- Restoring requires `git checkout` of the entire xcschemes directory
- This makes xc-project MCP unsafe for production use

## Likely Cause

The XCBuildCore library may be:
1. Re-serializing the entire project bundle including schemes
2. Dropping schemes that reference targets it doesn't fully understand
3. Having a bug in how it handles scheme preservation during writes

## Suggested Fix

1. Before writing project changes, snapshot the xcschemes directory
2. After writing, restore any deleted/modified scheme files
3. Or: Only write to project.pbxproj, never touch xcshareddata/