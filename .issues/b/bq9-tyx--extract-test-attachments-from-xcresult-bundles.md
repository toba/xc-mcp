---
# bq9-tyx
title: Extract test attachments from xcresult bundles
status: completed
type: feature
priority: normal
created_at: 2026-02-26T01:56:41Z
updated_at: 2026-02-26T02:06:16Z
sync:
    github:
        issue_number: "144"
        synced_at: "2026-02-26T02:22:31Z"
---

## Context

When running tests with `result_bundle_path`, the xcresult bundle captures test attachments (screenshots, data files) added via `XCTAttachment`. Currently there's no MCP tool to list or extract these attachments — users must manually run `xcresulttool export attachments` via shell commands.

## Use Case

Agent-driven visual verification workflows: run a UI test that captures screenshots, then extract and view them without leaving the MCP tool layer. Example from thesis project's `RealDatabaseTests` which screenshots sidenote popovers for visual inspection.

## Proposed Tools

### `get_test_attachments`
List and optionally extract attachments from an xcresult bundle.

**Inputs:**
- `result_bundle_path` (required) — path to `.xcresult`
- `test_id` (optional) — filter to specific test (e.g. `RealDatabaseTests/testFoo()`)
- `output_path` (optional) — directory to export files to; if omitted, return metadata only

**Output:**
- List of attachments with name, UUID, timestamp, MIME type, associated test
- If `output_path` provided, export files and return their paths

## Implementation Notes

- `xcresulttool get test-results activities --path <bundle> --test-id <id>` returns attachment metadata in JSON (payloadId, name, uuid)
- `xcresulttool export attachments --path <bundle> --output-path <dir>` exports all; can filter by test ID
- The test ID format requires trailing `()` on method names: `Class/testMethod()`
- Existing `XCResultParser` already shells out to `xcresulttool` — follow the same pattern

## Summary of Changes

- Added `GetTestAttachmentsTool` in `Sources/Tools/MacOS/GetTestAttachmentsTool.swift`
- Registered as `get_test_attachments` in both `BuildMCPServer` (xc-build) and `XcodeMCPServer` (xc-mcp)
- Added 5 unit tests in `Tests/GetTestAttachmentsToolTests.swift`
- Uses `xcrun xcresulttool export attachments` with manifest.json parsing
- Supports `test_id`, `output_path`, and `only_failures` filtering
