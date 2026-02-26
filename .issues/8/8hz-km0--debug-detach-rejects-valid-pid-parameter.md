---
# 8hz-km0
title: debug_detach rejects valid PID parameter
status: ready
type: bug
priority: normal
tags:
    - LLDB
created_at: 2026-02-26T01:04:03Z
updated_at: 2026-02-26T01:04:03Z
sync:
    github:
        issue_number: "143"
        synced_at: "2026-02-26T01:16:53Z"
---

## Problem

After attaching to a process with `debug_attach_sim(pid: 90022)`, calling `debug_detach(pid: 90022)` fails with:

```
Invalid params: Either bundle_id (with active session) or pid is required
```

The PID was provided but the tool rejected it. This left the process in a suspended state (TNX) that couldn't be killed with SIGKILL until the orphaned LLDB process was found and killed manually.

## Impact

- Can't cleanly detach from debugged processes
- Process gets stuck in suspended state
- Requires manual `pkill -f lldb` cleanup

## TODO

- [ ] Fix PID parameter handling in debug_detach
- [ ] Ensure detach properly resumes the process before disconnecting
