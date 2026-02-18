---
# ebq-mmq
title: swift-frontend SILGen crash when building IceCubesApp fixture
status: ready
type: bug
priority: high
created_at: 2026-02-18T01:29:46Z
updated_at: 2026-02-18T01:29:46Z
sync:
    github:
        issue_number: "65"
        synced_at: "2026-02-18T01:30:12Z"
---

## Description

\`swift test\` crashes swift-frontend every time when compiling the IceCubesApp fixture for the integration test \`buildRunScreenshot_IceCubesApp_sim\`.

The crash is in SILGen during \`Transform::transform\` when lowering a KeyPath expression involving typed throws function conversions. Stack trace shows:
- \`emitFunction(FuncDecl*)\` → \`visitVarDecl\` → \`emitKeyPathComponentForDecl\` → \`visitKeyPathExpr\` → \`Transform::transform\` → SIGTRAP

This is a Swift 6.2.3 compiler bug (Xcode 16.4) triggered by IceCubesApp source code, not xc-mcp code.

## Impact

- All integration tests that build IceCubesApp are blocked
- \`swift test\` gets killed due to the crash
- Non-integration unit tests (430+) pass fine

## Workaround Options

- [ ] Disable IceCubesApp integration tests until Xcode 16.5/Swift 6.3
- [ ] Pin IceCubesApp fixture to an older commit that doesn't trigger the crash
- [ ] Add \`--skip\` filter to CI test command to exclude integration tests
- [ ] File Apple Feedback with crash report

## Environment

- Swift 6.2.3 (swiftlang-6.2.3.3.21)
- macOS 15.7.4
- Xcode 16.4
