---
# kr2-5d0
title: ""
status: completed
type: task
priority: normal
created_at: 2026-07-08T16:20:48Z
updated_at: 2026-07-08T16:20:48Z
---

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
