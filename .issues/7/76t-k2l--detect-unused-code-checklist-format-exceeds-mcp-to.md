---
# 76t-k2l
title: detect_unused_code checklist format exceeds MCP token limit
status: completed
type: bug
priority: normal
created_at: 2026-03-07T21:42:31Z
updated_at: 2026-03-07T21:42:36Z
sync:
    github:
        issue_number: "183"
        synced_at: "2026-03-07T21:43:02Z"
---

## Problem

`detect_unused_code` with `format: "checklist"` dumps every declaration as a numbered line item. For large projects (e.g. Thesis with 1000+ unused declarations), this produces 180K+ characters — exceeding the MCP maximum allowed tokens.

## Fix

- Remove separate "checklist" format — a checklist is now always created on disk automatically
- Summary/detail output stays compact (counts by kind, top files); never dumps the full item list
- Checklist progress (pending/done/skipped/false_positive counts) shown inline when items have been marked
- `mark` parameter works with any format for iterative cleanup
- Checklist path included in output so agents can reference it

## Checklist

- [x] Remove `formatChecklist` and `checklistPageSize`
- [x] Always create checklist in `execute()` regardless of format
- [x] Add `formatChecklistProgress` helper for inline progress
- [x] Update `formatSummary` and `formatDetail` to accept checklist state
- [x] Update tool description and schema
- [x] Update tests (35 passing)


## Summary of Changes

Replaced the separate `format: "checklist"` mode (which dumped all items, causing token overflow) with always-on checklist tracking. The checklist file is created on disk automatically; summary/detail output remains compact with inline progress counts. The `mark` parameter works with any format.
