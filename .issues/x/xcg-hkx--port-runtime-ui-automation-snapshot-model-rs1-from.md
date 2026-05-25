---
# xcg-hkx
title: 'Port runtime UI-automation snapshot model (rs/1) from XcodeBuildMCP #416 to simulator tools'
status: ready
type: feature
priority: normal
created_at: 2026-05-25T15:53:22Z
updated_at: 2026-05-25T15:53:22Z
sync:
    github:
        issue_number: "332"
        synced_at: "2026-05-25T16:02:48Z"
---

Port the runtime UI-automation snapshot model from XcodeBuildMCP PR #416 (commit `857954e`, "rs/1 runtime automation parity") to our **iOS-simulator** UI tools in `Sources/Tools/UIAutomation/`.

## Upstream summary

PR #416 doesn't add tools — it changes what existing simulator action tools (tap/swipe/type_text/…) *return*. Each action now returns a compact `rs/1` runtime snapshot of the foreground UI plus app-agnostic next-step suggestions, so the agent can chain actions without re-snapshotting or screenshotting between steps. Upstream reports 67–76% reductions in tokens/calls/wall-clock. The whole design rests on a **simulator accessibility snapshot** that emits stable element refs (`e1`, `e2`, …); action tools then take `elementRef` instead of raw `x`/`y`.

Key upstream helpers (`src/mcp/tools/ui-automation/shared/`): `snapshot-ui-state.ts` (per-sim snapshot store w/ TTL + `resolveElementRef` + serialized AX transaction), `runtime-snapshot.ts` (`rs/1` format, roles/labels/identifiers/frames/state, **screenHash** for change detection, derived activation/swipe points, row caps), `post-action-snapshot.ts` (refresh after action but **preserve action success if refresh fails**), `runtime-next-steps.ts` (app-agnostic tap/type/scroll candidate ranking), `semantic-tap.ts`, `wait-predicate.ts`.

## What we already have

- `Sources/Core/NextStepHints.swift` — the output-rendering layer (ported from PR #420). Right place to plug runtime-derived suggestions in, but currently has no UI-state input.
- `Sources/Tools/Interact/` (8 macOS tools) — already element-based over the macOS AX API. **None of PR #416 ports here directly**; macOS already has an element model. Optional borrow: screenHash change-detection + next-step ranking → NextStepHints.

## Gaps (all iOS-simulator-specific, in `Sources/Tools/UIAutomation/`)

Our 8 simulator tools are purely coordinate-based (`TapTool` takes only `x`/`y`; no snapshot store, no AX query, no `wait_for_ui`/`batch`/`key_sequence`).

- [ ] **1. Simulator accessibility snapshot + element-ref store (FOUNDATIONAL — gates everything)** — new `snapshot_ui`-style tool that reads the simulator accessibility hierarchy and assigns stable refs, backed by an in-memory per-simulator store with TTL and `resolveElementRef`. Decide on AX source (AXe CLI, `simctl` accessibility, or our own).
- [ ] **2. Element-ref-based actions** — extend tap/swipe/type_text/long_press/button/gesture to accept `elementRef` resolved against the store (keep coordinate fallback).
- [ ] **3. Post-action runtime capture** — return compact foreground snapshot + screenHash in each action result, with the "preserve success if refresh fails" guarantee. Headline token-saving feature.
- [ ] **4. Runtime-derived next steps** — feed ranked candidates from the snapshot into existing `NextStepHints`. Closes the loop with the helper we already shipped.
- [ ] **5. `wait_for_ui` tool** — predicate polling (`exists`/`gone`/`enabled`/`focused`/`textContains`/`settled`).
- [ ] **6. `batch` tool** — multiple tap steps in one call with ax-cache modes (`perBatch`/`perStep`/`none`).
- [ ] **7. `key_sequence` tool / daemon-routed `key_press`** — we have `KeyPressTool` but no `key_sequence`; key path isn't routed through a shared simulator session.

## Suggested sequencing

Item 1 is the prerequisite. Items 2–4 deliver the token-reduction payoff. Items 5–7 are independent follow-ons that also depend on item 1.

## Source

- Upstream: getsentry/XcodeBuildMCP PR #416, commit `857954e2031660e5b4b8c6e69c2537a84bc42518`
- Tracked via `jig cite` (getsentry/XcodeBuildMCP source)
