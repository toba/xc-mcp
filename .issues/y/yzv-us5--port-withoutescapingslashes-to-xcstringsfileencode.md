---
# yzv-us5
title: Port withoutEscapingSlashes to XCStringsFileEncoder
status: completed
type: feature
priority: normal
created_at: 2026-05-09T15:20:55Z
updated_at: 2026-05-09T15:38:13Z
sync:
    github:
        issue_number: "316"
        synced_at: "2026-05-09T15:41:57Z"
---

Port xcstrings-crud PR #30 (commit 2380a6e1, fixes their #28) to our `Sources/Core/XCStrings/XCStringsFileEncoder.swift`. `JSONEncoder` escapes `/` as `\/` by default, which is valid JSON but not what Xcode produces. Setting `.outputFormatting = [..., .withoutEscapingSlashes]` eliminates noisy diffs in catalogs that contain strings like "Domestic / Foreign".

Source: https://github.com/Ryu0118/xcstrings-crud/pull/30

- [x] Add `.withoutEscapingSlashes` to the encoder's `outputFormatting`
- [x] Add a round-trip test using a key/value containing `/`



## Summary of Changes

- `Sources/Core/XCStrings/XCStringsFileEncoder.swift::jsonEscaped()` now configures `JSONEncoder` with `.withoutEscapingSlashes` so emitted strings contain literal `/` instead of `\/`. Only the final render path needed the change (the inner `encodeJSONValue` decodes back through `JSONSerialization`, which strips escaping).
- `Tests/XCStringsUpstreamPortTests.swift` adds `encoder does not escape forward slashes` round-tripping a `Domestic / Foreign` value and asserting no `\/` appears in the output.
