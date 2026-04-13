---
# 323-p9s
title: Bump XcodeProj to 9.11.0, add debugAsWhichUser to create_scheme
status: completed
type: task
priority: normal
created_at: 2026-04-13T16:29:56Z
updated_at: 2026-04-13T16:41:33Z
sync:
    github:
        issue_number: "281"
        synced_at: "2026-04-13T16:43:37Z"
---

- [x] Run swift package update to pull XcodeProj 9.11.0
- [x] Add optional debug_as_which_user parameter to CreateSchemeTool
- [x] Pass it through to XCScheme.LaunchAction initializer
- [x] Add test coverage (4 tests)
