---
# oh0-b83
title: 'xcstrings: respect shouldTranslate=false entries'
status: completed
type: bug
priority: normal
created_at: 2026-05-04T15:28:17Z
updated_at: 2026-05-04T15:44:57Z
sync:
    github:
        issue_number: "308"
        synced_at: "2026-05-04T15:45:35Z"
---

Upstream fix in Ryu0118/xcstrings-crud@9803d77: `StringEntry` may carry `shouldTranslate: false` to mark a key as non-translatable. Our `Sources/Core/XCStrings/Models/XCStringsModels.swift` does not decode this field, so:

- `listUntranslated(for:)` reports non-translatable keys as missing
- `checkCoverage(_:)` counts them against coverage
- `XCStringsStatsCalculator.getStats()` divides translated by total including non-translatable entries

Fix:
- Add `shouldTranslate: Bool?` to `StringEntry` and `KeyInfo` in `Sources/Core/XCStrings/Models/XCStringsModels.swift`
- Add a `requiresTranslation` computed property (`shouldTranslate != false`)
- Filter `requiresTranslation` in `XCStringsReader.listUntranslated` and `checkCoverage` (return 100% coverage for non-translatable)
- Filter in `XCStringsStatsCalculator.getStats`
- Pass `shouldTranslate` through when building `KeyInfo` in `getKey`

Reference: https://github.com/Ryu0118/xcstrings-crud/commit/9803d77

## Tasks
- [x] Add field to model + KeyInfo
- [x] Filter in reader (listUntranslated, checkCoverage)
- [x] Filter in stats calculator
- [x] Add test fixture with shouldTranslate=false
- [x] Verify round-trip preserves the field



## Summary of Changes

- Added `shouldTranslate: Bool?` to `StringEntry` and `KeyInfo` in `Sources/Core/XCStrings/Models/XCStringsModels.swift` plus a `requiresTranslation` computed property (`shouldTranslate != false`).
- `XCStringsReader.listUntranslated` skips `requiresTranslation == false` entries; `checkCoverage` short-circuits to 100% with no missing languages for them.
- `XCStringsStatsCalculator.getStats` filters `file.strings.values` to translatable entries before per-language counting, so non-translatable keys no longer drag coverage down.
- `getKey` passes `shouldTranslate` through into `KeyInfo`.
- New tests in `Tests/XCStringsUpstreamPortTests.swift` cover all three behaviors plus round-trip preservation.

All 1100 tests pass.
