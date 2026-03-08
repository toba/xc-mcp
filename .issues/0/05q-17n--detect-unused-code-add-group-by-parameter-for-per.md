---
# 05q-17n
title: 'detect_unused_code: add group_by parameter for per-target summaries'
status: completed
type: feature
priority: normal
tags:
    - enhancement
created_at: 2026-03-08T00:02:53Z
updated_at: 2026-03-08T00:14:38Z
sync:
    github:
        issue_number: "188"
        synced_at: "2026-03-08T00:43:51Z"
---

## Problem

When a user wants a per-target breakdown of unused code, they currently need to make one `detect_unused_code` call per module path (using `file_filter`), then mentally stitch results together. For a project with 18 modules that's 18+ tool calls — slow, token-heavy, and unnecessary.

## Proposed Solution

Add a `group_by` parameter (e.g. `group_by: "target"` or `group_by: "module"`) that returns the summary broken down by Xcode target or top-level directory.

### Example output (single call)

```
1272 unused declarations across 471 files

By target:
  Core              538  (166 files)  — method (162), property (133), static property (75)
  Tests             186  (45 files)   — method (82), property (49), static property (15)
  DocX              110  (56 files)   — method (42), property (19), constructor (10)
  ThesisApp          92  (38 files)   — property (25), static property (18), method (15)
  CSL                76  (43 files)   — method (33), property (26), constructor (6)
  DOM                69  (28 files)   — method (24), property (24), constructor (7)
  MathView           63  (24 files)   — property (29), static property (8), method (8)
  Zotero             63  (33 files)   — method (12), static property (9), constructor (8)
  RIS                 8  (3 files)    — struct (2), enum (2), static method (2)
  EndNote             6  (3 files)    — enum (2), struct (2), extension (1)
  TableView           3  (1 file)     — struct (1), property (1), constructor (1)
  BibTeX              3  (2 files)    — static method (1), var (1), struct (1)
  Scrivener           0
  Ulysses             0
  ...
```

### Implementation notes

- The target association is already available in Periphery's JSON output (each declaration has a module/target)
- If Periphery doesn't emit target info, infer from file paths using the project's target-to-directory mapping (already known from the xcodebuild index)
- `group_by: "directory"` could be a simpler alternative — group by first 2 path components relative to project root (e.g. `Core/Sources`, `Integrations/Zotero`, `Components/MathView`)
- Should work with `result_file` for cached results too
- Keep existing `file_filter` behavior as-is for drilling into a single target

## Acceptance

- [x] Single tool call produces per-target unused code counts with top kinds
- [x] Works with both fresh scans and `result_file` cached results


## Summary of Changes

- Added `modules` field to `PeripheryEntry` and `module` field to `UnusedDeclaration` — Periphery JSON already includes `modules` array but it was not being parsed
- Added `group_by` parameter accepting `"target"`, `"kind"`, or `"directory"`
- `target`: groups by module name from Periphery output (falls back to `(unknown)` if missing)
- `kind`: groups by declaration kind (func, property, import, etc.)
- `directory`: groups by last two directory components of the file path
- Each group line shows: name, count, file count, and top 3 declaration kinds
- Added `directoryGroup()` helper for path-based grouping
- Added 10 new tests covering all group_by modes, filtered counts, empty modules, and module parsing
