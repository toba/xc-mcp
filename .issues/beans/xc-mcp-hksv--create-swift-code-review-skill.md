---
# xc-mcp-hksv
title: Create Swift code review skill
status: completed
type: task
priority: normal
created_at: 2026-01-21T17:06:54Z
updated_at: 2026-01-21T17:09:46Z
sync:
    github:
        issue_number: "26"
        synced_at: "2026-02-15T22:08:23Z"
---

Create a skill that analyzes Swift code for:
- Shared functionality that can be factored out
- Similar functions that can be combined using generics
- Opportunities for typed throws
- Opportunities for structured concurrency

The skill should run swiftlint and swift format before analysis.
