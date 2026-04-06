---
# bsm-83m
title: Add memory diagnostic tools (leaks, heap, vmmap, stringdups, malloc_history)
status: completed
type: feature
priority: normal
created_at: 2026-04-06T23:17:25Z
updated_at: 2026-04-06T23:32:04Z
sync:
    github:
        issue_number: "265"
        synced_at: "2026-04-06T23:36:27Z"
---

Wrap Xcode's memory diagnostic CLI tools as MCP tools, likely in the Debug server.

An LLM can run these on a running process, parse the dense output, and surface actionable findings.

## Tools

- [x] `memory_leaks` — run `leaks <pid>`, parse leaked objects with backtraces
- [x] `memory_heap` — run `heap <pid> --sortBySize`, show heap allocations by class/size
- [x] `memory_vmmap` — run `vmmap <pid>`, summarize virtual memory regions (dirty/clean/swapped)
- [x] `memory_stringdups` — run `stringdups <pid>`, find duplicate strings wasting memory
- [x] `memory_malloc_history` — run `malloc_history <pid> <address>`, show allocation backtrace (requires MallocStackLogging)

## Notes

- These work on running processes by PID — integrate with existing session/process tracking
- Output is dense text; parsers should extract structured summaries
- `malloc_history` requires the target process was launched with `MallocStackLogging=1`
- Could also support `.memgraph` file analysis for offline diagnostics

## Reference

Discovered via https://github.com/Terryc21/Xcode-tools catalog of hidden Xcode CLI tools.


## Summary of Changes

Added 5 memory diagnostic tools to the Debug server wrapping `leaks`, `heap`, `vmmap`, `stringdups`, and `malloc_history`. All accept `pid` or `bundle_id` for target resolution via a new `resolveTargetPID()` extension on `[String: Value]`. Registered in both the Debug focused server and the monolithic server.
