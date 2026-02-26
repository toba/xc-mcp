---
# 6x9-9il
title: get_test_attachments parses manifest.json with wrong keys, returns Unnamed/unknown for all attachments
status: completed
type: bug
priority: high
tags:
    - test
    - xcresult
created_at: 2026-02-26T03:19:37Z
updated_at: 2026-02-26T03:28:25Z
sync:
    github:
        issue_number: "146"
        synced_at: "2026-02-26T03:41:26Z"
---

## Problem

`get_test_attachments` returns `Unnamed` for attachment names and `unknown` for filenames because it parses the xcresulttool manifest.json using incorrect keys. The manifest has a nested structure that doesn't match the flat parsing logic.

### Actual manifest schema (from `xcresulttool export attachments --schema`)

```json
[
  {
    "testIdentifier": "TargetName/TestClass/testMethod()",
    "attachments": {
      "exportedFileName": "actual-file.png",
      "suggestedHumanReadableName": "SideNoteCitation-RealDB",
      "isAssociatedWithFailure": false,
      "timestamp": 1740529200.0,
      "configurationName": "...",
      "deviceName": "...",
      "deviceId": "..."
    }
  }
]
```

### Current parsing (wrong)

The code in `formatManifest()` reads from a flat `[String: Any]`:
- `entry["name"]` → should be `attachment["suggestedHumanReadableName"]`
- `entry["fileName"]` → should be `attachment["exportedFileName"]`
- `entry["testName"]` → should come from outer `testIdentifier`
- `entry["isFailure"]` → should be `attachment["isAssociatedWithFailure"]`

### Expected behavior

The tool should:
1. Parse the outer array to get `testIdentifier` per test
2. Iterate the `attachments` object/array within each test entry
3. Use the correct schema keys: `suggestedHumanReadableName`, `exportedFileName`, `isAssociatedWithFailure`
4. Map exported files to their actual paths in the output directory

### Reproduction

Run any XCUI test that creates an `XCTAttachment` with a custom name, export with `get_test_attachments`, observe all attachments show as `Unnamed` with `File: unknown`.

## Files

- `Sources/Tools/MacOS/GetTestAttachmentsTool.swift` — fix manifest parsing in `execute()` and `formatManifest()`
- `Tests/GetTestAttachmentsToolTests.swift` — update tests with realistic manifest structure


## Summary of Changes

### `GetTestAttachmentsTool.swift`
- **Fixed manifest parsing**: Rewrote to handle the actual nested xcresulttool manifest schema — outer array of `{ testIdentifier, attachments }` entries where `attachments` is an object or array with `exportedFileName`, `suggestedHumanReadableName`, `isAssociatedWithFailure`, and `timestamp` keys.
- Extracted `flattenManifest()` (static) to convert nested manifest into flat `[Attachment]` array.
- Extracted `formatAttachments()` (static) for output formatting.
- Handles both single-object and array forms of the `attachments` field.
- Falls back to `exportedFileName` when `suggestedHumanReadableName` is missing.

### `GetTestAttachmentsToolTests.swift`
- Added 7 new tests covering: nested array parsing, single object parsing, fallback name, entries without attachments, formatting with/without export dir.
