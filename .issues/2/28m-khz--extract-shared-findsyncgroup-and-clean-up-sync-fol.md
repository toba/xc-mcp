---
# 28m-khz
title: Extract shared findSyncGroup and clean up sync folder tools
status: completed
type: task
priority: normal
created_at: 2026-02-21T21:13:59Z
updated_at: 2026-02-21T21:20:07Z
---

## Context

Swift review found duplicated code and inconsistencies across the synchronized folder tools added in recent changes.

## Checklist

- [x] Extract `findSyncGroup(_:in:)` into a shared utility (duplicated across 5 files: RemoveTargetFromSynchronizedFolderTool, ListSynchronizedFolderExceptionsTool, RemoveSynchronizedFolderExceptionTool, AddSynchronizedFolderExceptionTool, AddTargetToSynchronizedFolderTool)
- [x] Normalize URL construction to use `URL(filePath:)` consistently in RemoveGroupTool.swift and ListFilesTool.swift (currently using older `URL(fileURLWithPath:)`)
- [x] Extract shared test helper for sync folder project setup (repeated ~15-line boilerplate in RemoveSynchronizedFolderExceptionToolTests, RemoveTargetFromSynchronizedFolderToolTests, ListSynchronizedFolderExceptionsToolTests)
- [x] Evaluate typed throws (`throws(MCPError)`) for execute methods — decide if worth adopting codebase-wide or deferring
- [x] Review `removeChildren(of:from:)` in RemoveGroupTool for iterative alternative (low priority, current recursive approach is fine for practical depths)


## Summary of Changes

- Created `SynchronizedFolderUtility.swift` with shared `findSyncGroup` method, removed duplicate from 5 tool files
- Normalized `URL(fileURLWithPath:)` to `URL(filePath:)` in RemoveGroupTool and ListFilesTool
- Added `TestProjectHelper.createTestProjectWithSyncFolder()` helper, simplified 3 test files
- Typed throws: deferred — only 16 of 156 tools use the MCPError rethrow pattern; not worth adopting in isolation
- `removeChildren` recursion: no change needed — correct for shallow Xcode group trees
