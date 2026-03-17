---
# mx2-mwz
title: Wait for process exit after SIGTERM in stop/terminate tools
status: completed
type: bug
priority: normal
created_at: 2026-03-17T18:26:26Z
updated_at: 2026-03-17T20:02:53Z
blocked_by:
    - x62-nw2
sync:
    github:
        issue_number: "221"
        synced_at: "2026-03-17T20:06:38Z"
---

\`SwiftPackageStopTool\` sends \`pkill -15/-9\` and returns immediately without confirming the process actually exited. Same fire-and-forget pattern in \`LogCapture.stopCapture\` (bare \`kill\`) and \`LLDBRunner.terminate()\` (detached Task with no await).

Discovered via citation review of getsentry/XcodeBuildMCP \`c4ece28a\` which fixed this in their \`swift_package_stop\`.

## Affected files
- \`Sources/Tools/SwiftPackage/SwiftPackageStopTool.swift\` — add poll/wait after \`pkill\`
- \`Sources/Core/ProcessResult.swift\` (\`LogCapture.stopCapture\`) — wait for exit after \`kill\`
- \`Sources/Core/LLDBRunner.swift\` (\`terminate()\`) — await the detached Task or use \`waitUntilExit()\`

## Approach
After sending the signal, poll with \`kill -0 <pid>\` or use \`waitpid\` to confirm exit, with a bounded timeout and SIGKILL escalation.


## Summary of Changes

- Extracted ProcessResult.waitForProcessExit(pid:timeout:) — polls kill -0 with configurable timeout (also deduplicated from StopMacAppTool)
- SwiftPackageStopTool: captures PIDs via pgrep before pkill, waits for exit, escalates to SIGKILL
- LogCapture.stopCapture: waits for exit after SIGTERM, escalates to SIGKILL for PID-based kills
- LLDBRunner.terminate(): now async — quit → 2s wait → SIGTERM → 3s wait → SIGKILL, always closes PTY FDs
