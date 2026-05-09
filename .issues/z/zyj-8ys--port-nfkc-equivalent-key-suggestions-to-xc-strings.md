---
# zyj-8ys
title: Port NFKC-equivalent key suggestions to xc-strings tools
status: completed
type: feature
priority: normal
created_at: 2026-05-09T15:20:55Z
updated_at: 2026-05-09T15:38:15Z
sync:
    github:
        issue_number: "315"
        synced_at: "2026-05-09T15:41:57Z"
---

Port xcstrings-crud PR #29 (commit 1384fa79) to our `Sources/Core/XCStrings/` so that `checkKey` / `getKey` / `getTranslation` / `checkCoverage` surface 'Did you mean: …?' suggestions when a queried key differs only by NFKC-equivalence from an existing key (most common case: APOSTROPHE U+0027 vs RIGHT SINGLE QUOTATION MARK U+2019, which Xcode emits for keys like "Record today's progress").

Upstream changes:
- `XCStringsError.keyNotFound` gains `suggestions: [String]` and appends "Did you mean: …?" when present
- `XCStringsReader` adds `suggestions(for:)` using NFKC normalization
- `XCStringsParser` exposes `suggestions(for:)` at the package level
- `CheckKeyHandler` returns `false (key not found; did you mean: …?)` instead of bare `false`

Source: https://github.com/Ryu0118/xcstrings-crud/pull/29

- [x] Add NFKC-based `suggestions(for:)` lookup in our XCStrings reader/parser
- [x] Wire suggestions into the relevant tool error responses
- [x] Add tests covering U+0027 → U+2019 lookup miss with suggestion



## Summary of Changes

- `Sources/Core/XCStrings/XCStringsError.swift` — `keyNotFound` gains a `suggestions: [String] = []` associated value; `errorDescription` appends `Did you mean: '…'?` when non-empty.
- `Sources/Core/XCStrings/XCStringsReader.swift` — adds `suggestions(for:)`. Uses NFKC (`precomposedStringWithCompatibilityMapping`) plus an explicit curly-quote fold (U+2019/U+2018 → `'`, U+201C/U+201D → `"`). Note: the upstream commit message claims pure NFKC handles the U+0027 vs U+2019 case, but it does not — those codepoints are not compatibility-equivalent. The quote fold is required to actually deliver the documented behavior. All three `keyNotFound` throw sites in the reader now pass `suggestions:`.
- `Sources/Core/XCStrings/XCStringsParser.swift` — exposes `suggestions(for:)` on the actor.
- `Sources/Tools/XCStrings/XCStringsCheckKeyTool.swift` — when `checkKey` returns `false` and suggestions exist, the tool returns `false (key not found; did you mean: '…'?)` instead of bare `false`.
- `Tests/XCStringsUpstreamPortTests.swift` — adds three tests: `suggestions returns NFKC-equivalent existing keys`, `keyNotFound includes NFKC suggestions in its description`, `suggestions are empty when no NFKC equivalent exists`.

Upstream `XCStringsWriter` throw sites (delete/rename/update key) were intentionally left as `keyNotFound(key:)` — the default empty `suggestions` argument keeps existing call sites compiling and the writer doesn't currently surface error messages to the user; can be revisited if a writer-error path benefits from suggestions.
