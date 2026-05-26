---
# y2e-stg
title: Evaluate post-action UI snapshot settling for UIAutomation tools
status: completed
type: task
priority: normal
created_at: 2026-05-26T15:01:43Z
updated_at: 2026-05-26T15:15:17Z
sync:
    github:
        issue_number: "343"
        synced_at: "2026-05-26T15:17:10Z"
---

## Context

Upstream getsentry/XcodeBuildMCP commit 3eaed16 (#427, cameroncooke, 2026-05-26) introduced a 'settled post-action runtime snapshot' pattern: mutating UI actions (button tap, key press) now wait for a stable UI runtime snapshot before returning, so the next agent step receives stable element refs rather than a snapshot captured mid-transition.

Relevant upstream files:
- src/mcp/tools/ui-automation/shared/post-action-snapshot.ts
- src/mcp/tools/ui-automation/button.ts
- src/mcp/tools/ui-automation/key_press.ts

## Goal

Evaluate whether xc-mcp's UI automation tools (Sources/Tools/UIAutomation/ for simulator, and possibly Sources/Tools/Interact/ for macOS accessibility) would benefit from a similar post-action settling step — waiting for a stable accessibility/UI snapshot after a mutating action before returning refs to the agent.

## Tasks

- [x] Review current behavior of mutating UIAutomation tools (tap/swipe/key) — do they return immediately or already wait for settle?
- [x] Compare against upstream post-action-snapshot approach
- [x] Decide whether to adopt; if so, scope the implementation (shared helper in Core vs per-tool)

## Source

Surfaced via /cite review of getsentry/XcodeBuildMCP.

## Summary of Changes

### Findings

- **Before:** All mutating tools were fire-and-forget. macOS `interact_*` tools read element refs from a cache populated by a *prior* `interact_ui_tree` call, so refs went stale after any UI change. Only `navigateMenu()` had a fixed `Thread.sleep(0.1)`.
- **Simulator UIAutomation tools** (`tap`, `swipe`, `button`, etc.) use raw `simctl io` coordinates and have **no accessibility/UI tree source** anywhere in the codebase — nothing to snapshot, and coordinate input does not suffer stale-ref issues. Out of scope; left unchanged.
- The settle + stable-ref value applies to the **macOS Interact tools**, which do expose an AX tree.

### Implementation (decision: full settle + auto-snapshot for macOS Interact)

- `InteractRunner.settledUITree(pid:maxDepth:timeout:pollInterval:)` — polls the AX tree until two consecutive structural snapshots match (settled) or an 800ms timeout. `async throws` so `CancellationError` from `Task.sleep` propagates per MCP cancellation rules.
- `InteractRunner.fingerprint(_:)` — structural signature (element summaries joined) for change detection.
- `InteractPostAction.settledSnapshot(runner:pid:maxDepth:)` (new `Sources/Core/InteractPostAction.swift`) — settles, refreshes the `InteractSessionManager` cache, and returns a formatted tree to append to the tool response.
- Wired into `interact_click`, `interact_set_value`, `interact_focus`, `interact_menu`, and `interact_key`. Existing success messages are preserved; the settled tree is appended. `interact_menu`/`interact_key` became `async` (dispatch updated in `XcodeMCPServer.swift`); `interact_key` gained optional app-resolution args and only snapshots when a target app is identified (CGEvents are global).
- Tests: `Tests/InteractSettleTests.swift` (5 tests) covering fingerprint determinism, value/focus/enabled/child changes, and order sensitivity. All pass; full build green.

### Not adopted

- Simulator UIAutomation auto-snapshot — would require building a simulator accessibility-describe capability that does not exist; tracked as potential future work.
