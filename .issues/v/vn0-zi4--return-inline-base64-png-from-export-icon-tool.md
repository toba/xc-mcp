---
# vn0-zi4
title: Return inline base64 PNG from export_icon tool
status: completed
type: task
priority: normal
created_at: 2026-04-13T16:29:56Z
updated_at: 2026-04-13T16:41:33Z
sync:
    github:
        issue_number: "280"
        synced_at: "2026-04-13T16:43:37Z"
---

- [x] Read exported PNG file after ictool renders it
- [x] Return .image(data: base64, mimeType: image/png) like ScreenshotMacWindowTool does
- [x] Keep text description as secondary content item
- [x] Add test coverage (updated integration test)
