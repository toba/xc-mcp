---
# 8mr-d95
title: detect_unused_code result_file returns stale entries from prior scans
status: completed
type: bug
priority: normal
created_at: 2026-03-08T01:35:30Z
updated_at: 2026-03-08T01:41:19Z
sync:
    github:
        issue_number: "189"
        synced_at: "2026-03-08T01:42:29Z"
---

## Problem

When using `detect_unused_code` with `result_file` to drill into cached results, the tool returns entries from prior scan checklists that lack `#N` indices. These stale entries:

1. Cannot be marked via `mark` (no indices)
2. Cannot be marked via `mark_filtered` (not in current checklist)
3. Keep appearing as "pending" even after the underlying code has been fixed or annotated

## Expected Behavior

`result_file` should only return results from the scan that produced that specific JSON file. Entries from prior checklist files should not leak into current results.

## Reproduction

1. Run `detect_unused_code` scan → produces `/tmp/periphery-<hash>.json` and checklist
2. Fix some items, mark them in checklist
3. Query with `result_file` + `status_filter: ["pending"]`
4. Results include entries without `#N` indices that cannot be resolved through the tool

## Impact

Agent workflow stalls because it cannot clear these ghost entries. The count never reaches zero even when all code changes are complete.


## Summary of Changes

Delete the old checklist file when a new Periphery scan writes its cache file. Since there's one cache/checklist pair per project (keyed by hash), this ensures a stale checklist from a prior scan never persists across rescans.
