---
# kk3-3q2
title: Add crash symbolication tool (atos)
status: completed
type: feature
priority: normal
created_at: 2026-04-06T23:17:27Z
updated_at: 2026-04-06T23:32:04Z
sync:
    github:
        issue_number: "266"
        synced_at: "2026-04-06T23:36:27Z"
---

Wrap `atos` as an MCP tool for symbolicating crash log addresses.

## Tool

- [x] `symbolicate_address` — run `atos -o <binary> -arch <arch> -l <load_address> <addresses...>`

## Capabilities

- Convert raw memory addresses to `ClassName.method + offset`
- Accept multiple addresses in one call for batch symbolication
- Auto-detect architecture from binary when possible
- Support both dSYM and binary paths

## Notes

- Complements existing `search_crash_reports` tool
- Essential for diagnosing unsymbolicated crash logs from devices/TestFlight
- Could also wrap `crashlog` for full .crash file symbolication

## Reference

Discovered via https://github.com/Terryc21/Xcode-tools catalog.


## Summary of Changes

Added `symbolicate_address` tool wrapping `xcrun atos`. Supports binary/dSYM file symbolication with load address, or live process attachment via PID. Batch symbolicates multiple addresses in one call. Registered in Debug server and monolithic server.
