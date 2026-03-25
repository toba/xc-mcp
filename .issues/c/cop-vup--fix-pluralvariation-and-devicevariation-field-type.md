---
# cop-vup
title: Fix PluralVariation and DeviceVariation field types to match xcstrings format
status: completed
type: bug
priority: normal
created_at: 2026-03-25T20:39:59Z
updated_at: 2026-03-25T20:41:23Z
sync:
    github:
        issue_number: "239"
        synced_at: "2026-03-25T20:44:32Z"
---

Upstream fix from Ryu0118/xcstrings-crud (d2a1fbd). In xcstrings JSON, each plural/device variation value is wrapped: `{ "stringUnit": { "state": "...", "value": "..." } }`. Our models decode directly as `StringUnit?`, missing the wrapper object. This causes silent decode failures for any .xcstrings file with plural or device variations.

- [x] Add `VariationValue` wrapper type
- [x] Update `PluralVariation` fields from `StringUnit?` to `VariationValue?`
- [x] Update `DeviceVariation` fields from `StringUnit?` to `VariationValue?`
- [x] Verify with tests


## Summary of Changes

Added `VariationValue` wrapper struct and changed `PluralVariation` and `DeviceVariation` fields from `StringUnit?` to `VariationValue?` to match the actual xcstrings JSON structure where each variation value is `{ "stringUnit": { ... } }` rather than a bare `StringUnit`.
