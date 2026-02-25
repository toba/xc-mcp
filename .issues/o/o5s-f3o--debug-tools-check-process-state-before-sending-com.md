---
# o5s-f3o
title: 'debug tools: check process state before sending commands'
status: ready
type: feature
created_at: 2026-02-25T02:01:18Z
updated_at: 2026-02-25T02:01:18Z
---

Debug tools like \`debug_view_hierarchy\` blindly send LLDB commands without checking process state first. When the process is stopped (crashed, breakpoint), sending \`continue\` + expression evaluation causes cascading failures:

1. \`debug_view_hierarchy\` sent \`continue\` to a crashed process
2. The process re-raised SIGABRT
3. The expression eval failed (\`NSApplication\` not found since ObjC wasn't loaded)
4. The tool returned a confusing mix of assembly + errors

**Proposed fix:** Before sending diagnostic commands that require a running process (view hierarchy, expression eval), check \`process status\`. If stopped:
- Return a clear error: "Process is stopped (SIGABRT). Use debug_stack or debug_continue first."
- Or for tools like \`debug_stack\` and \`debug_variables\` that work on stopped processes, proceed normally

This is a cross-cutting concern for all debug tools. Could be a shared helper in LLDBRunner that categorizes tools as "needs running process" vs "works on stopped process".
