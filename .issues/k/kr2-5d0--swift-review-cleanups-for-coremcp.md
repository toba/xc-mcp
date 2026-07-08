---
# kr2-5d0
title: Swift review cleanups for Core/MCP
status: completed
type: task
priority: normal
created_at: 2026-07-08T16:17:22Z
updated_at: 2026-07-08T16:17:22Z
sync:
    github:
        issue_number: "419"
        synced_at: "2026-07-08T16:45:30Z"
---

Apply /swift review findings to Sources/Core/MCP: typed throws, naming (bundleID), Task name, dup extraction, ingest reverse-scan, cached JSONEncoder.

## Summary of Changes

Applied `/swift` review findings to `Sources/Core/MCP/`:

- **ArgumentExtraction.swift**
  - `getRequiredString` → `throws(MCPError)` (typed throws)
  - `parseBatchTranslationEntries` → `throws(MCPError)`; converted `compactMap` to a `reserveCapacity`'d `for` loop so typed throws propagates
  - Extracted shared `stringValues(from:)` helper; `getStringDictionary` and the batch-translation parser now reuse it
  - Renamed local `bundleId` → `bundleID` in `resolveTargetPID`/`resolveDebugPID` (acronym casing)
- **ProgressReporter.swift**
  - Named the poll task `Task(name: "progress-poll")`
  - Replaced `chunk.split(...).reversed()` in `ingest` with a backward-scanning `lastNonBlankLine(in:)` helper — no `[Substring]` allocation on the streaming hot path
- **NextStepHints.swift**
  - Cached the `JSONEncoder` as a `static let` instead of allocating one per `HintValue.rendered` call

Build succeeds. 31 relevant tests pass (ProgressReporter, NextStepHints, TestIdentifierNormalization).

Not done (out of scope): the remaining `bundleId:` acronym lint warning at ArgumentExtraction.swift:353 is the public `getPID(bundleId:)` label declared in LLDBRunner.swift and used at 12 call sites across Debug/MacOS tools — a separate refactor. Warning count for the directory went 6 → 1.
