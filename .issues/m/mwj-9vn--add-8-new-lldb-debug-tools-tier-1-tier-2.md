---
# mwj-9vn
title: Add 8 new LLDB debug tools (Tier 1 + Tier 2)
status: completed
type: feature
priority: normal
created_at: 2026-02-15T16:10:26Z
updated_at: 2026-02-15T16:14:03Z
---

Implement debug_evaluate, debug_threads, debug_watchpoint, debug_step, debug_memory, debug_symbol_lookup, debug_view_hierarchy, debug_process_status tools.

## Tasks
- [x] Create 8 tool source files in Sources/Tools/Debug/
- [x] Add 8 LLDBRunner methods to Sources/Core/LLDBRunner.swift
- [x] Register tools in XcodeMCPServer.swift (enum, instantiation, listTools, callTool)
- [x] Register tools in DebugMCPServer.swift (enum, instantiation, listTools, callTool)
- [x] Verify swift build compiles cleanly
- [x] Verify swift test passes (315 tests)

## Summary of Changes

Added 8 new LLDB debug tools to close gaps in the interactive debugging loop:

1. **debug_evaluate** - Evaluate expressions (po/p/expr with language support)
2. **debug_threads** - List threads and optionally select one
3. **debug_watchpoint** - Manage watchpoints (add/remove/list with conditions)
4. **debug_step** - Step through code (in/over/out/instruction)
5. **debug_memory** - Read memory at addresses (hex/bytes/ascii/instruction formats)
6. **debug_symbol_lookup** - Look up symbols, addresses, and types
7. **debug_view_hierarchy** - Dump UI view hierarchy (iOS/macOS)
8. **debug_process_status** - Get current process state

Files created: 8 tool files in Sources/Tools/Debug/
Files modified: LLDBRunner.swift (8 methods), XcodeMCPServer.swift, DebugMCPServer.swift
