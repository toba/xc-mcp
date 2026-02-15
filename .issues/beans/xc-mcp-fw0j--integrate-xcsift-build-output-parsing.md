---
# xc-mcp-fw0j
title: Integrate xcsift build output parsing
status: completed
type: feature
priority: normal
created_at: 2026-01-31T16:39:43Z
updated_at: 2026-01-31T16:51:56Z
sync:
    github:
        issue_number: "17"
        synced_at: "2026-02-15T22:08:23Z"
---

Port xcsift's OutputParser, Models, and CoverageParser into xc-mcp Sources/Core/, add a BuildResultFormatter, update all build/test tools to use structured parsing, and add tests.

## Checklist
- [x] Add BuildOutputModels.swift (adapted from xcsift Models.swift)
- [x] Add BuildOutputParser.swift (adapted from xcsift OutputParser.swift)  
- [x] Add CoverageParser.swift (adapted from xcsift CoverageParser.swift)
- [x] Add BuildResultFormatter.swift (formatting helper for MCP output)
- [x] Update ErrorExtraction.swift to use BuildOutputParser
- [x] Update build tools (BuildSimTool, BuildRunSimTool, BuildMacOSTool, BuildRunMacOSTool, BuildDeviceTool, SwiftPackageBuildTool, CleanTool)
- [x] Update test tools (TestSimTool, TestMacOSTool, TestDeviceTool, SwiftPackageTestTool)
- [x] Add test fixtures (build.txt, swift-testing-output.txt, linker-error-output.txt)
- [x] Add tests (BuildOutputParserTests, LinkerErrorTests, CoverageTests, BuildResultFormatterTests)
- [x] Update Package.swift for test resources
- [x] Verify swift build compiles cleanly
- [x] Verify swift test passes
- [x] Run swift format and swiftlint
