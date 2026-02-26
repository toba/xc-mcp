---
# b5r-x0z
title: build_debug_macos times out with stop_at_entry
status: ready
type: bug
priority: normal
tags:
    - macOS
    - LLDB
created_at: 2026-02-26T01:03:56Z
updated_at: 2026-02-26T01:03:56Z
sync:
    github:
        issue_number: "142"
        synced_at: "2026-02-26T01:16:49Z"
---

## Problem

`build_debug_macos` with `stop_at_entry: true` times out:

```
LLDB command failed: Timed out waiting for LLDB response.
Partial output: process attach --name "ThesisApp (debug)" --waitfor
```

The tool uses `--waitfor` which waits for a process with matching name to launch, but either:
1. The launch doesn't happen in time
2. The process name doesn't match (e.g. due to spaces/parens in name)
3. The LLDB timeout is too short for the build+launch sequence

## Workaround

Manual LLDB launch with script file works fine:
```bash
lldb -s script.lldb -- "/path/to/App"
```

## TODO

- [ ] Diagnose why build_debug_macos times out
- [ ] Increase timeout or use PID-based attach instead of name-based waitfor
- [ ] Handle app names with spaces/parens correctly
