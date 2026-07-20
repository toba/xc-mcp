---
# gmn-wlq
title: Evaluate reusable prepared test artifacts for build/test tools
status: completed
type: feature
priority: normal
created_at: 2026-07-20T18:54:46Z
updated_at: 2026-07-20T19:03:23Z
sync:
    github:
        issue_number: "430"
        synced_at: "2026-07-20T19:04:10Z"
---

Upstream XcodeBuildMCP added support for reusable prepared test artifacts (commit e21bf43, PR #475): split build-for-testing from test-without-building so a compiled test bundle can be re-run without rebuilding.

Idea worth evaluating for xc-mcp: allow test_macos / swift_package_test (and device/sim test tools) to prepare a test bundle once and re-run it across multiple invocations without recompiling — a speedup for iterative test runs.

Reference: https://github.com/getsentry/XcodeBuildMCP/commit/e21bf437b923d9717624b6c97c9d367dbf210dff

Notes from upstream design:
- Keep source-only xcodebuild args out of the generated test-without-building phase
- Preserve explicit test destinations and only-testing/skip-testing selectors into the prepared phase
- Reject device destinations without prepared tests; only mark successful test products complete (with retention cap)
- Extract failures from managed result bundles

The manifest-driven conditional next-steps part is XcodeBuildMCP-specific architecture and does not map to our tool structure — skip that.

Surfaced via /cite review of getsentry/XcodeBuildMCP.

## Summary of Changes

**Evaluation outcome:** xc-mcp already deterministically scopes `-derivedDataPath` per project+platform (`DerivedDataScoper`), so compiled test bundles already persist across tool calls — the upstream "prepared-artifact key + session retention" machinery is unnecessary here. The whole value of the upstream feature reduces to one thing: letting the test tools skip the build/planning phase and run the already-compiled bundle via xcodebuild's `test-without-building`. The scoped DerivedData *is* the stable artifact reference, so no new session state, key, or bundle-tracking was needed.

**Implemented** a `without_building` option on `test_macos`, `test_sim`, and `test_device`:

- `XcodebuildRunner.test()` gained a `withoutBuilding` flag; the `test` vs `test-without-building` action selection (plus the whole test-arg assembly) was extracted into a new testable static `XcodebuildRunner.testArgs(...)`. The scoped `-derivedDataPath` and the `-only-testing`/`-skip-testing`/`-testPlan`/`-destination` selectors are all preserved into the without-building phase (satisfies the upstream "preserve selectors/destinations" note). `RawBuildLog` now records the actual action.
- Shared `withoutBuildingSchemaProperty` added in `ArgumentExtraction`, merged into all three test tools; the flag is plumbed through `TestToolHelper.runAndFormat`.
- Failure extraction already reads from managed `.xcresult` bundles (`XCResultParser` / `TestResultBundleScoper`), so the upstream "extract failures from managed result bundles" note was already satisfied — no change needed.

**Deliberately out of scope:**
- `swift_package_test` — SwiftPM's `swift test` has no build/test split (no `test-without-building` equivalent), so it can't support this. Left unchanged.
- Device pre-flight rejection — rather than replicate the upstream "reject device destinations without prepared tests" gate, we let `xcodebuild` surface its own clear error when products are missing (documented in the param description that a prior run is required). Kept the surface minimal.
- No new `build-for-testing` "prepare" tools for sim/device: a normal test/build run already populates the scoped DerivedData, which is all `test-without-building` needs. `build_macos`'s existing `for_testing` remains available as an explicit prepare step.

**Tests:** `Tests/TestWithoutBuildingArgsTests.swift` (4 tests) covers action selection and selector/destination/coverage preservation in `testArgs`. Passing.

Files: `Sources/Core/Runners/XcodebuildRunner.swift`, `Sources/Core/MCP/ArgumentExtraction.swift`, `Sources/Core/Testing/TestToolHelper.swift`, `Sources/Tools/{MacOS/TestMacOSTool,Simulator/TestSimTool,Device/TestDeviceTool}.swift`, `Tests/TestWithoutBuildingArgsTests.swift`.
