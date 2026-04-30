---
# qps-3nm
title: Stream swift build/test progress to MCP client
status: ready
type: feature
priority: normal
created_at: 2026-04-30T16:03:15Z
updated_at: 2026-04-30T16:03:15Z
sync:
    github:
        issue_number: "298"
        synced_at: "2026-04-30T16:11:23Z"
---

Today, swift_package_build and swift_package_test buffer all output until the process exits, so a 10-minute swift-syntax compile looks like a hang. Pipe periodic last-line snapshots (e.g. 'Compiling SwiftSyntax SyntaxNodes02.swift') back to the client via MCP progress notifications or a tail-style status field on the next tool result. No speedup — pure UX. Builds on the partial-output capture already in `XcodebuildRunner.timeout(duration:partialOutput:)`.

Follow-up to tc2-9jv.
