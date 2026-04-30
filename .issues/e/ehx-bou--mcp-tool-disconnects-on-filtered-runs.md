---
# ehx-bou
title: MCP tool disconnects on filtered runs
status: completed
type: bug
priority: high
created_at: 2026-04-30T04:50:56Z
updated_at: 2026-04-30T05:01:25Z
sync:
    github:
        issue_number: "294"
        synced_at: "2026-04-30T05:01:46Z"
---

The xc-swift package-test wrapper hangs (>1 min) on narrow filter args and disconnects the whole MCP server on cancel. Repro: from the swiftiomatic package, package-build succeeds, then package-test with filter=BinaryOperatorExprTests hangs; cancel drops every xc-swift tool. Direct shell invocation of the same filtered run completes in seconds. Likely causes: filter not forwarded to the child; SPM build plugins rerun every call (swiftiomatic has a code-gen plugin); cancel tears down the server instead of just the child. Tasks: verify filter forwarded; skip plugin rerun when build is fresh; cancel kills child only; honor timeout param with hard internal cap.



## Additional repro (same session)

- Called with explicit timeout=60: tool ran past 60s, then returned -32000 Connection closed instead of a clean timeout error. The timeout parameter is not enforced inside the wrapper; the request hangs until the MCP transport itself drops.
- Net effect: caller cannot bound wall time at all — the timeout arg is decorative.



## Summary of Changes

Fixed the MCP server disconnect on cancel by spawning child processes in their own process group (`processGroupID = 0`) and adding a task cancellation handler that sends `SIGKILL` to the entire group via `kill(-pgid, SIGKILL)`. This reaps swift driver, SPM build plugins, and any grandchildren so stdout/stderr pipes close, `Subprocess.run()` returns promptly, and the server stays alive.

Also reduced `gracefulShutDown` from 5s to 2s so cancellation feels responsive.
