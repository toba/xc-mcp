---
# xc-mcp-ck35
title: Integrate xcstrings-crud as xc-strings MCP server
status: completed
type: feature
priority: normal
created_at: 2026-01-21T16:53:28Z
updated_at: 2026-01-21T17:03:17Z
---

Port localization functionality from Ryu0118/xcstrings-crud as a new focused MCP server (xc-strings) following xc-mcp's established multi-server architecture.

## Checklist

- [x] Port core library to Sources/Core/XCStrings/
  - [x] Create XCStringsModels.swift with Codable types
  - [x] Create XCStringsError.swift with MCPError mapping
  - [x] Create XCStringsFileHandler.swift for file I/O
  - [x] Create XCStringsReader.swift for read operations
  - [x] Create XCStringsWriter.swift for write operations
  - [x] Create XCStringsStatsCalculator.swift for statistics
  - [x] Create XCStringsParser.swift as facade actor
- [x] Create tool structs (18 tools)
- [x] Create StringsMCPServer.swift
- [x] Create CLI.swift entry point
- [x] Update Package.swift with xc-strings target
- [x] Update LICENSE with xcstrings-crud attribution
- [x] Update README.md with new server documentation
- [x] Verify: swift build compiles
- [x] Verify: swift format and swiftlint pass