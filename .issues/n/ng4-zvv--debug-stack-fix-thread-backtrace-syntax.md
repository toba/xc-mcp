---
# ng4-zvv
title: 'debug_stack: fix thread backtrace syntax'
status: completed
type: bug
priority: high
created_at: 2026-02-25T02:00:43Z
updated_at: 2026-02-25T02:05:33Z
sync:
    github:
        issue_number: "131"
        synced_at: "2026-02-25T02:05:46Z"
---

\`getStack(pid:threadIndex:)\` in \`LLDBRunner.swift:870\` uses \`thread backtrace --thread N\` which is invalid LLDB syntax. The \`--thread\` flag doesn't exist — LLDB parses it as an unknown option and errors:

```
thread backtrace --thread 1
                  ^~~~~~~~
                  error: unknown or ambiguous option
```

**Fix:** Use \`bt N\` (positional thread count) or \`thread backtrace\` with \`thread select N\` first. The correct single-command form for a specific thread is either:
- \`thread backtrace -t N\` (if \`-t\` is supported in that LLDB version)
- \`bt\` after \`thread select N\`

Discovered during a Thesis debugging session where \`debug_stack\` with \`thread: 1\` failed, requiring fallback to \`debug_lldb_command\` with raw \`bt\`.


## Summary of Changes

Fixed `getStack(pid:threadIndex:)` in `LLDBRunner.swift` to use `thread select N` followed by `thread backtrace` instead of the invalid `thread backtrace --thread N` syntax. The `--thread` flag does not exist in LLDB; the previous code produced an "unknown or ambiguous option" error when a specific thread index was requested.
