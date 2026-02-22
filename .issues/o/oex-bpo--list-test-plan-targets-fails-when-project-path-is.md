---
# oex-bpo
title: list_test_plan_targets fails when project_path is relative (empty searchRoot)
status: completed
type: bug
priority: high
created_at: 2026-02-22T02:06:45Z
updated_at: 2026-02-22T02:12:10Z
---

## Problem

When `project_path` is relative (e.g. `"Thesis.xcodeproj"`), `findTestPlanTargets` computes an empty `searchRoot`:

```swift
projectRoot = (projectPath as NSString).deletingLastPathComponent  // "" for relative path
```

`FileManager.enumerator(atPath: "")` returns `nil`, so the method silently returns `[]` and the tool reports:

```
(no targets found — .xctestplan file may be missing)
```

...even though the `.xctestplan` file exists at the project root with valid targets.

This affects both the Build server and any server using `ListTestPlanTargetsTool` when session defaults use relative paths (which is common since `set_session_defaults` accepts relative paths).

### Discovered

During a Thesis session where `set_session_defaults` was called with `project_path: "Thesis.xcodeproj"`. The `iOS Tests.xctestplan` file was at the same level and had a valid `AppTests` target entry, but the tool returned no targets.

## TODO

- [x] Fix `searchRoot` computation to handle relative paths (e.g. use `"."` when `deletingLastPathComponent` returns `""`)
- [x] Add test case for relative `project_path` with `.xctestplan` at project root


## Summary of Changes

Fixed `searchRoot` computation in `ListTestPlanTargetsTool.execute` to use `"."` when `NSString.deletingLastPathComponent` returns an empty string (which happens with relative paths like `"Thesis.xcodeproj"`). Changed `findTestPlanTargets` from `private` to `package` access for testability. Added 4 unit tests covering absolute paths, dot-relative paths, empty search root, and subdirectory discovery.
