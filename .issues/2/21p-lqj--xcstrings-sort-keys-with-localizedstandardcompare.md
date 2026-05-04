---
# 21p-lqj
title: 'xcstrings: sort keys with localizedStandardCompare to match Xcode'
status: completed
type: bug
priority: low
created_at: 2026-05-04T15:28:18Z
updated_at: 2026-05-04T15:44:57Z
sync:
    github:
        issue_number: "306"
        synced_at: "2026-05-04T15:45:32Z"
---

Upstream fix in Ryu0118/xcstrings-crud@84ae167: Xcode sorts string keys with `localizedStandardCompare` (natural ordering), not lexicographic. Plain `.sorted()` on key arrays produces noisy diffs whenever Xcode re-saves a catalog after we write it.

Affected sites in `Sources/Core/XCStrings/XCStringsReader.swift`:
- L10 `listKeys`: `file.strings.keys.sorted()`
- L35 `listUntranslated` final `.sorted()`
- L108 `.sorted()` on key set
- (language sorts L21/L45/L124 are fine — Xcode sorts BCP-47 codes lexicographically)

Plus the writer in `XCStringsWriter.swift` should emit keys in this order so on-disk diffs stay clean. The upstream patch introduces a custom `XCStringsFileEncoder` that renders keys in sorted order with a deterministic format (`"key" : value`); we may not need the full encoder but should at least sort key emission.

Fix:
- Add `XCStringsKeySorter` (or extension) using `localizedStandardCompare` with lexicographic fallback for stability
- Replace the three `sorted()` call sites in reader
- Verify writer emits keys in the same order

Reference: https://github.com/Ryu0118/xcstrings-crud/commit/84ae167

## Tasks
- [x] Add XCStringsKeySorter helper
- [x] Update reader sort sites
- [x] Update writer key ordering
- [x] Test against an Xcode-saved fixture to confirm zero-diff round trip



## Summary of Changes

- New `Sources/Core/XCStrings/XCStringsKeySorter.swift` sorts via `localizedStandardCompare` with a lexicographic tiebreak.
- New `Sources/Core/XCStrings/XCStringsFileEncoder.swift` ports the upstream encoder so `XCStringsFileHandler.save`/`create` emit Xcode's exact format: `"key" : value` with space before colon, top-level `sourceLanguage` / `strings` / `version` order, sorted nested object keys, and `strings` keyed in `localizedStandardCompare` order.
- `XCStringsReader.listKeys`, `listUntranslated`, and `listStaleKeys` now use the sorter.
- Tests cover the natural sort, the Xcode key-colon-value format, and top-level field ordering.
