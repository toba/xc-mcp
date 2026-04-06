---
# j7c-tup
title: Add asset catalog validation tool (actool)
status: completed
type: feature
priority: normal
created_at: 2026-04-06T23:17:30Z
updated_at: 2026-04-06T23:32:05Z
sync:
    github:
        issue_number: "264"
        synced_at: "2026-04-06T23:36:27Z"
---

Wrap `actool` validation as an MCP tool for pre-build asset checking.

## Tool

- [x] `validate_asset_catalog` — run `actool --warnings --errors --notices --output-format human-readable-text --validate <path.xcassets>`

## Capabilities

- Validate .xcassets for missing sizes, incorrect formats, invalid configurations
- Report warnings/errors before they become build failures
- Could also use `amlint` if available for deeper linting

## Notes

- `actool` lives inside Xcode toolchain (`xcrun actool`)
- Useful as a pre-build check or CI gate
- Parse output to extract structured warning/error list

## Reference

Discovered via https://github.com/Terryc21/Xcode-tools catalog.


## Summary of Changes

Added `validate_asset_catalog` tool wrapping `xcrun actool` in validation mode. Reports warnings, errors, and notices for .xcassets directories. Supports platform and deployment target parameters. Registered in Build server and monolithic server.
