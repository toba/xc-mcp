---
# ilx-kbr
title: Evaluate periphery Equatable/Hashable property retention impact on detect_unused_code
status: completed
type: task
priority: normal
created_at: 2026-05-21T16:01:15Z
updated_at: 2026-05-21T16:25:25Z
sync:
    github:
        issue_number: "324"
        synced_at: "2026-05-21T16:26:56Z"
---

Upstream commit peripheryapp/periphery@b4e202dc adds an `EquatableHashablePropertyRetainer` SourceGraph mutator that retains properties referenced by synthesized/manual Equatable/Hashable conformances.

This changes which symbols periphery considers unused. `mcp__xc-swift__detect_unused_code` wraps periphery, so results may shift for projects with Equatable/Hashable types.

## Tasks
- [ ] Confirm the periphery version we invoke (BinaryLocator + version pin, if any)
- [ ] Check whether `detect_unused_code` results change once periphery is upgraded to a release containing this commit
- [ ] Update tool documentation / next-step hints if behavior meaningfully changes
- [ ] Decide if any fixture-based tests need updating



## Summary of Changes

Added two passthrough boolean params to `detect_unused_code`:
- `retain_equatable_properties` → `--retain-equatable-properties`
- `retain_hashable_properties` → `--retain-hashable-properties`

Both default to false (matching periphery defaults). Suppresses false positives on stored properties of value types (struct/enum) that conform to Equatable/Hashable, where compiler-synthesized `==` / `hash(into:)` don't emit index references.

Requires periphery containing PR #1126 (post-3.7.4, not yet released as of 2026-05-21). Pure additive change — no schema / output / test fixture changes needed.

Files: `Sources/Tools/SwiftPackage/DetectUnusedCodeTool.swift` (schema + arg extraction + arg passthrough)
