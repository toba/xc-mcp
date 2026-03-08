---
# o3p-0sg
title: sample_mac_app should parse and summarize results, not dump raw text
status: completed
type: feature
priority: normal
tags:
    - xc-build
created_at: 2026-03-08T05:25:28Z
updated_at: 2026-03-08T05:36:38Z
blocked_by:
    - 3vb-iba
sync:
    github:
        issue_number: "192"
        synced_at: "2026-03-08T05:42:30Z"
---

## Problem

After capturing a `sample` trace (proposed in 3vb-iba), the agent still has to do extensive grep/awk/sed work to extract actionable information from 50K+ lines of raw output. In the thesis profiling session, it took ~8 tool calls of increasingly creative grep pipelines to find that `SQLMigration.runSchemas` was the bottleneck.

## What the tool should do automatically

### 1. Filter idle stacks
Strip `mach_msg_trap`, `__psynch_cvwait`, `kevent`, and other idle/waiting frames. Only return stacks where the process was actually doing work.

### 2. Aggregate by function
Return a sorted table of heaviest functions with cumulative sample counts:

```
Samples | Function                          | Source
--------|-----------------------------------|---------------------------
   282  | SQLMigration.runSchemas           | SQLMigration.swift:44
   198  | SQLCreator.createTrigger          | SQLCreator.swift:103
    76  | CloudKitSchema.createTriggers     | CloudKitSchema.swift:51
```

### 3. Filter to app code
By default, only show frames from the app's own dylib (the `.debug.dylib` or main binary), not system frameworks. Option to include system frames.

### 4. Show heaviest call paths
Collapse the tree into the top N heaviest unique call paths through app code:

```
282 samples: SQLMigration.register → .migrate → .run → .runSchemas → NodeSchema.createTriggers → SQLCreator.createTrigger
```

### 5. Per-thread summary
Show which threads were busy vs idle, with the heaviest app function per thread.

## Input parameters

- `filter`: `"app"` (default) | `"all"` — whether to include system framework frames
- `top_n`: number of heaviest functions/paths to return (default 20)
- `thread`: `"main"` (default) | `"all"` | specific thread name — which threads to analyze

## Why this matters

The whole point of an MCP profiling tool is that the agent can act on the results in one round-trip. Raw `sample` output requires the agent to be a grep expert and wastes 5-10 tool calls on text processing instead of fixing the actual bug.


## Summary of Changes

### New: `SampleOutputParser` (`Sources/Core/SampleOutputParser.swift`)

Parses raw `/usr/bin/sample` output into structured, agent-friendly summaries:

1. **Section splitting** — separates header, call graph, and binary images
2. **Call graph tree building** — parses indented frame lines into a proper tree using depth detection
3. **Idle frame filtering** — strips `mach_msg_trap`, `__workq_kernreturn`, `__psynch_cvwait`, and 15+ other waiting/idle functions
4. **System library filtering** — in `app` mode (default), only shows frames from the app binary, not system frameworks
5. **Function aggregation** — aggregates leaf frames by function name, sorted by sample count
6. **Call path extraction** — collapses trees into heaviest unique call paths through app code (`A → B → C`)
7. **Thread summary** — shows all threads with sample counts and idle/active status
8. **Formatted output** — produces markdown-style report with tables and sections

### Updated: `sample_mac_app` tool

New parameters:
- `filter`: `"app"` (default) or `"all"` — controls whether system framework frames are included
- `top_n`: number of heaviest functions/paths to return (default 20)
- `thread`: `"main"` (default), `"all"`, or a thread name substring
- `raw`: `true` to bypass parsing and return raw sample output

### Tests

- 15 new tests in `SampleOutputParserTests.swift` covering section splitting, tree building, idle detection, system library detection, filtering, aggregation, and full summarization
- 4 existing `SampleMacAppToolTests` continue to pass
