---
# oqt-7l7
title: Add --build-tests flag to swift_package_build
status: completed
type: feature
priority: normal
created_at: 2026-02-23T00:16:23Z
updated_at: 2026-02-23T00:30:33Z
---

## Problem

\`swift_package_build\` only exposes \`configuration\` and \`product\` parameters. There is no way to build test targets without compiling and running them.

During this session, verifying that new integration test files compiled required \`swift build --build-tests\` via bash — the MCP tool couldn't do it.

## Acceptance Criteria

- [x] Add \`build_tests\` boolean parameter to \`swift_package_build\` tool
- [x] When true, pass \`--build-tests\` to \`swift build\`
- [x] Update SwiftRunner.build() to accept the flag


## Summary of Changes

Added `build_tests` boolean parameter to `SwiftPackageBuildTool` schema and `SwiftRunner.build()`. When true, passes `--build-tests` to `swift build`.
