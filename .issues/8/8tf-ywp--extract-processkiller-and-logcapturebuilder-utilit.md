---
# 8tf-ywp
title: Extract ProcessKiller and LogCaptureBuilder utilities
status: completed
type: task
priority: high
created_at: 2026-02-19T20:12:54Z
updated_at: 2026-02-19T20:36:15Z
sync:
    github:
        issue_number: "84"
        synced_at: "2026-02-19T20:42:41Z"
---

Extract duplicated process kill/stop logic (~100 lines each) from 3 logging tools, and log capture setup from 3 start tools.

Kill logic in: StopSimLogCapTool:48-112, StopDeviceLogCapTool:48-109, StopMacLogCapTool:42-84
Setup logic in: StartSimLogCapTool:85-118, StartDeviceLogCapTool:87-150, StartMacLogCapTool:64-120

- [ ] Create ProcessKiller utility (killByPID, killByPattern, appendTailOutput)
- [ ] Create LogCaptureBuilder utility (createOutputFile, buildLogStreamArgs)
- [ ] Refactor 3 stop tools to use ProcessKiller
- [ ] Refactor 3 start tools to use LogCaptureBuilder
- [ ] Verify tests pass
