---
# tn0-xgm
title: Add environment variable and skip filter support to swift_package_test
status: ready
type: feature
priority: normal
created_at: 2026-02-23T00:16:26Z
updated_at: 2026-02-23T00:16:26Z
---

## Problem

\`swift_package_test\` only exposes \`filter\` (positive match). Missing:

1. **Environment variables** — can't pass \`RUN_SLOW_TESTS=1\` to enable conditional test suites via \`.enabled(if: ProcessInfo.processInfo.environment[...] != nil)\`. This is a common swift-testing pattern.

2. **Skip filter** (\`--skip\`) — can only include tests, not exclude them. Swift 6's \`swift test --skip <pattern>\` is the complement to \`--filter\`.

3. **Parallel flag** (\`--parallel\`/\`--no-parallel\`) — no control over test parallelism.

During this session, the \`RUN_SLOW_TESTS\` gating pattern was implemented but is unreachable through the MCP tool.

## Acceptance Criteria

- [ ] Add \`env\` parameter (object/dict) to \`swift_package_test\` — passed as environment to subprocess
- [ ] Add \`skip\` parameter (string) — maps to \`swift test --skip <pattern>\`
- [ ] Add \`parallel\` parameter (boolean) — maps to \`--parallel\`/\`--no-parallel\`
- [ ] Add environment variable passthrough to \`ProcessResult.runSubprocess()\`
