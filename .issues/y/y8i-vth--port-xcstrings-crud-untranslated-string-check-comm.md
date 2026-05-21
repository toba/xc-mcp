---
# y8i-vth
title: Port xcstrings-crud untranslated string check command
status: completed
type: feature
priority: normal
created_at: 2026-05-21T16:01:15Z
updated_at: 2026-05-21T16:25:25Z
sync:
    github:
        issue_number: "323"
        synced_at: "2026-05-21T16:26:56Z"
---

Upstream commit Ryu0118/xcstrings-crud@9571198d adds an `Add untranslated string check command` to the CLI, with supporting changes in XCStringsKit (Models/XCStrings.swift, XCStringsParser.swift, XCStringsReader.swift) and new CheckCommand.swift.

We mirror this project closely in `Sources/Tools/XCStrings/` (24 tools) — port the untranslated-check capability as a new xc-strings tool.

## Tasks
- [ ] Read upstream commit + PR #33 (`feature/check-untranslated-hooks`)
- [ ] Decide tool name (e.g. `xcstrings_check_untranslated`)
- [ ] Implement reader/parser additions if needed
- [ ] Add tool + tests



## Summary of Changes

Ported Ryu0118/xcstrings-crud PR #33's untranslated-check semantics — our existing `xcstrings_list_untranslated` only checks for presence (`value != nil || variations != nil`) and silently misses empty values, `needs_review` state, and partial variation coverage.

Added:
- 3 new model types in `Sources/Core/XCStrings/Models/XCStringsModels.swift`: `UntranslatedReason` (8 cases), `UntranslatedIssue`, `UntranslatedCheckResult`.
- `XCStringsReader.checkUntranslated(languages:)` walks string units and plural/device variations, classifying each gap into one of: `missing_localization`, `missing_string_unit`, `empty_value`, `state_not_translated`, `missing_variation_values`, `missing_variation_string_unit`, `empty_variation_value`, `variation_state_not_translated`. Skips `shouldTranslate: false`.
- `XCStringsParser.checkUntranslated(languages:)` facade.
- New tool `xcstrings_check_untranslated` (`Sources/Tools/XCStrings/XCStringsCheckUntranslatedTool.swift`) accepting `file` and optional `languages` (defaults to all languages in the file).
- Wired into `StringsMCPServer` and `ServerToolDirectory` (xc-strings tool count now 25).

Tests: 5 new in `XCStringsUpstreamPortTests` covering missing-localization, empty-value (the listUntranslated blind spot), state\!=translated, empty plural variation, and shouldTranslate=false exclusion.

Skipped: upstream's `--codex-hook` / `--claude-hook` JSON envelopes — those are CLI-specific (MCP already returns structured JSON the agent reads directly). Kept `xcstrings_list_untranslated` unchanged so existing callers' key-list shape is preserved.
