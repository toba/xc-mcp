---
# 7vp-v06
title: Sweepable grep across test-plan files for rename refactors
status: completed
type: bug
priority: normal
created_at: 2026-06-03T16:30:23Z
updated_at: 2026-06-03T16:35:00Z
sync:
    github:
        issue_number: "382"
        synced_at: "2026-06-03T16:35:46Z"
---

During a bundle-ID rename pass in the Thesis project (vpo-ysy, dropping the `.editor` suffix on the release bundle), I needed to confirm no test-plan files referenced the old bundle ID string `com.thesisapp.editor`.

The Bash pre-tool hook blocks any command mentioning the test-plan file extension — correctly forcing test-plan edits through xc-mcp. But xc-mcp does not expose a way to grep test-plan file contents for arbitrary substrings. The existing tools (list_test_plans, add_target_to_test_plan, set_test_plan_skipped_tests, etc.) are operation-specific and do not help when you just need to know "does any test plan reference string X anywhere in its JSON."

For a rename/refactor sweep this leaves a gap. A workflow agent has two bad options:
1. Read every test-plan file individually via Read tool (slow, noisy, and the agent may not know which paths exist)
2. Skip the sweep and hope no test plan referenced the old string (risky)

Proposed fix: add either
- mcp__xc-project__search_test_plans — given a project path + search string, return matching test-plan files + JSON paths where the substring appears
- OR a generic mcp__xc-project__list_test_plan_settings — dump all test-plan settings as JSON for downstream grepping

Either would have closed the gap in one tool call instead of N.

Context: hit during Thesis vpo-ysy work splitting beta/release channels. Bundle ID rename from com.thesisapp.editor to com.thesisapp across pbxproj, entitlements, Swift, docs. xc-project handled pbxproj cleanly via find_build_settings + set_build_setting — test-plan equivalent is what is missing.



## Summary of Changes

Added `search_test_plans` to xc-project (and the monolithic xc-mcp server). Given a project path and substring, it walks every `.xctestplan` under the project parent and reports each match as a JSON path + value (or key match). Closes the rename-sweep gap so a single tool call replaces N `Read`s.

- New tool: `Sources/Tools/Project/SearchTestPlansTool.swift`
- Wired into `ProjectMCPServer` and `XcodeMCPServer` (enum case, instance, `ListTools` entry, dispatch arm)
- Tests: `Tests/SearchTestPlansToolTests.swift` (3 cases — substring match, no-match, case-insensitive)
