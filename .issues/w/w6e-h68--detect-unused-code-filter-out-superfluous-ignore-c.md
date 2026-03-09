---
# w6e-h68
title: 'detect_unused_code: filter out ''Superfluous ignore comment'' warnings'
status: completed
type: feature
priority: normal
created_at: 2026-03-09T00:23:58Z
updated_at: 2026-03-09T00:29:05Z
sync:
    github:
        issue_number: "198"
        synced_at: "2026-03-09T00:38:39Z"
---

## Problem

Periphery has a bug with assign-only properties: adding `// periphery:ignore` suppresses the "assign-only property" warning, but then Periphery reports "Superfluous ignore comment" for that same line. Removing the comment brings back the original warning. This creates an unresolvable cycle.

These warnings are never actionable — agents and users waste time removing ignore comments only to re-add them.

## Observed in

Thesis project CSL module: all 10 "unused code" results from CSL were superfluous-ignore warnings on decoded properties and test fixtures. Five prior cleanup rounds had already removed all real unused code.

## Proposed fix

In `detect_unused_code` result processing, filter out all results where the warning text starts with "Superfluous ignore comment". These are Periphery's own contradiction and provide no signal.

Optionally, surface a summary count like "10 superfluous ignore comment warnings filtered (Periphery bug)" so the user knows they exist but isn't asked to act on them.

## Workaround

Manually ignore the warnings each time they appear.

## Summary of Changes

Filtered out Periphery's `superfluousIgnoreComment` hints in `DetectUnusedCodeTool.execute()` before checklist creation. When superfluous warnings are filtered, a summary line is appended to the output (e.g. "10 superfluous ignore comment warning(s) filtered (Periphery bug)") so users know they exist without being asked to act on them.

- Added `filterSuperfluousIgnoreComments()` static method
- Applied filtering after parsing, before checklist creation
- Added 3 tests covering the filtering logic
