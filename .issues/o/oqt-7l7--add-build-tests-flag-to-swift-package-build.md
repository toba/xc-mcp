---
# oqt-7l7
title: Add --build-tests flag to swift_package_build
status: ready
type: feature
priority: normal
created_at: 2026-02-23T00:16:23Z
updated_at: 2026-02-23T00:16:23Z
---

## Problem

\`swift_package_build\` only exposes \`configuration\` and \`product\` parameters. There is no way to build test targets without compiling and running them.

During this session, verifying that new integration test files compiled required \`swift build --build-tests\` via bash — the MCP tool couldn't do it.

## Acceptance Criteria

- [ ] Add \`build_tests\` boolean parameter to \`swift_package_build\` tool
- [ ] When true, pass \`--build-tests\` to \`swift build\`
- [ ] Update SwiftRunner.build() to accept the flag
