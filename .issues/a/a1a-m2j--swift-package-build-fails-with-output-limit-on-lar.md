---
# a1a-m2j
title: swift_package_build fails with output limit on large projects
status: completed
type: bug
priority: normal
created_at: 2026-04-12T00:31:32Z
updated_at: 2026-04-12T01:01:58Z
sync:
    github:
        issue_number: "272"
        synced_at: "2026-04-12T01:02:57Z"
---

When building a 500+ file Swift package (swiftiomatic), both swift_package_build and swift_diagnostics fail with: MCP error -32603: Child process output exceeded the limit of 10485760 bytes. The 10MB limit is too low for large Swift projects. Either raise the limit, stream/truncate output intelligently, or return errors even when output is truncated.



## Summary of Changes

Changed `ProcessResult.runSubprocess` to use Subprocess's streaming closure API instead of `.string(limit:)`. When output exceeds the limit, the tail is kept (discarding the head) instead of throwing `SubprocessError.outputLimitExceeded`. Build errors always appear at the end of output, so nothing important is lost.

Also reduced default limits from 10MB to 2MB — 10MB of text is unreasonable and was masking the real problem. XCResultParser retains a higher 8MB limit for structured JSON data.

Files changed:
- `Sources/Core/ProcessResult.swift` — streaming tail-truncation, 2MB default
- `Sources/Core/XCResultParser.swift` — 31MB → 8MB limit
