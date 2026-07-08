---
# g0q-n0g
title: Fix PathUtility sandbox check rejecting all paths when base is filesystem root
status: completed
type: bug
priority: normal
created_at: 2026-07-08T18:07:11Z
updated_at: 2026-07-08T18:07:18Z
sync:
    github:
        issue_number: "421"
        synced_at: "2026-07-08T18:07:45Z"
---

The separator-anchored prefix check added in f655a48 computes basePath + "/" which becomes "//" when basePath is "/", so no absolute path matches and every path is rejected. Broke 11 CI tests (MoveFileTool, SearchTestPlansTool, AddTargetToTestPlanTool) that use basePath "/". Special-cased root in isPath.
