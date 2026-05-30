---
# o1b-ttp
title: Apply medium-priority /swift review fixes in Sources/Core
status: completed
type: task
priority: normal
created_at: 2026-05-30T14:24:26Z
updated_at: 2026-05-30T14:26:40Z
sync:
    github:
        issue_number: "365"
        synced_at: "2026-05-30T14:27:25Z"
---

From /swift review of Sources/Core:

- [x] Drop SimctlRunner.overrideStatusBar (weakly-typed [String: Any] wrapper); extend setStatusBar with cellularMode/wifiMode and update SimStatusBarTool to call it with named params.
- [x] Modernize SessionManager warmup task launch (line ~290) from Task.detached to Task.immediateDetached so warmup begins synchronously off the actor without a scheduling hop.
- [x] BuildSettingExtractor consolidation reviewed and skipped: apparent duplication is actually divergent defensive fallback paths (bundleId's JSON-ish text fallback differs intentionally from extractSetting's text fallback). Not worth the risk.


## Summary of Changes

- `Sources/Core/SimctlRunner.swift`: extended `setStatusBar` with `cellularMode` and `wifiMode` parameters; deleted the weakly-typed `overrideStatusBar(udid:options: [String: Any])` variant.
- `Sources/Tools/Simulator/SimStatusBarTool.swift`: rewritten to call `setStatusBar` with named arguments; replaced the `[String: Any]` options dictionary with a `setOptions: [String]` list used only for the success message.
- `Sources/Core/SessionManager.swift`: `Task.detached` → `Task.immediateDetached` on the warmup launch path. Behaviour is unchanged (detached + `.background` priority) but the warmup body now starts synchronously instead of going through a scheduler hop.
- `Sources/Core/PredicateFilterValidator.swift`: fixed a `switch` case introduced by `sm format` that lost its `continue` statement (build was broken until this commit).
- Verified: `swift build` clean; 38 targeted tests pass (Simctl / StatusBar / Session / Warmup / PredicateFilter).
