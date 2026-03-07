---
# yus-h26
title: detect_unused_code checklist doesn't reconcile with already-removed code
status: completed
type: bug
priority: normal
created_at: 2026-03-07T23:42:10Z
updated_at: 2026-03-07T23:47:02Z
sync:
    github:
        issue_number: "187"
        synced_at: "2026-03-07T23:47:27Z"
---

## Problem

When using `detect_unused_code` with `skip_build: true` and a cached `result_file`, items that have already been removed from source code still appear as **pending** in the checklist. The checklist has no mechanism to detect that the underlying declaration no longer exists in the codebase.

This causes confusion when reviewing remaining work — the same items keep surfacing even after they've been addressed in a prior commit.

## Example

1. Scan finds `protocol Delimitable` in `Protocols.swift` as redundant (#1060)
2. User removes the protocol and conformances, commits
3. Next review uses `result_file` + `status_filter: ["pending"]`
4. #1060 still shows as pending because nobody marked it done, and the tool doesn't check whether the declaration still exists

## Expected Behavior

When presenting checklist items from a cached result file, the tool should detect stale entries — declarations that no longer exist at the reported file:line — and either:

- Auto-mark them as `done` (with a note like "declaration no longer exists at reported location")
- Filter them out with a note in the summary (e.g. "12 stale items skipped — source changed since scan")
- At minimum, warn that the cached results may be stale relative to the current source

## Suggested Approach

Before presenting filtered results, do a quick existence check: for each pending item, verify the file still exists and optionally that the declaration name appears near the reported line. Items that fail the check get auto-resolved or flagged.

This is lightweight — it doesn't require re-running Periphery, just `stat` + optional line read.


## Summary of Changes

Updated `agentInstructions` in `DetectUnusedCodeTool.swift` to make checklist marking a **CRITICAL** requirement:
- Added explicit "IMMEDIATELY mark the item done" to steps 2 and 3
- Added new CRITICAL paragraph explaining that items must be marked AS YOU GO — after each resolution, before moving on
- Explains that unresolved items will persist as pending on the next call

No reconciliation logic needed — if the agent forgets, re-running the scan produces a fresh result set that excludes already-removed declarations.
