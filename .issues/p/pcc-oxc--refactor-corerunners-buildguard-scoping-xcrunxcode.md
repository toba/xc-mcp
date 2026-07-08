---
# pcc-oxc
title: 'Refactor Core/Runners: BuildGuard scoping, xcrun/xcodebuild arg helpers, AX hardening'
status: completed
type: task
priority: normal
created_at: 2026-07-08T16:50:35Z
updated_at: 2026-07-08T17:00:35Z
sync:
    github:
        issue_number: "420"
        synced_at: "2026-07-08T17:16:23Z"
---

Swift review cleanups for Sources/Core/Runners/: extract BuildGuard.withGuard; ProcessResult.xcrun helper; XcodebuildRunner projectArgs helper; navigateMenu async sleep; redundant AX children fetch; AX force-cast -> as?; Process xcrun factory; static JSONDecoder; task names.

## Summary of Changes

Consolidation and correctness cleanups across Sources/Core/Runners/:

- **BuildGuard.withGuard** — new scoped wrapper that releases the cross-process lock fd via defer on every exit path. Replaced manual acquire/do-catch/release triplets in SwiftRunner.run, XcodebuildRunner.run, and DetectUnusedCodeTool (extracted runPeriphery helper).
- **ProcessResult.xcrun(_:arguments:)** — shared xcrun-subtool invocation; SimctlRunner, DeviceCtlRunner, XctraceRunner now delegate to it.
- **Process.xcrun(_:arguments:)** factory — unstarted xcrun Process with stderr pipe; used by XctraceRunner.record and SimctlRunner.recordVideo.
- **XcodebuildRunner.projectArgs(...)** — one helper for the -workspace/-project + scoped -derivedDataPath prefix, replacing the block duplicated across build/buildTarget/test/clean/listSchemes/showBuildSettings.
- **InteractRunner** — eliminated the double AX children fetch per element (getAttributes now takes a precomputed childCount; single children(of:) helper reused by traverse/findChildByTitle/navigateMenu); replaced AXValue/AXUIElement force casts with CFGetTypeID-guarded casts (axValueAttribute helper); navigateMenu is now async using Task.sleep instead of blocking Thread.sleep.
- **Lint hygiene** — named all previously-unnamed Tasks/addTasks (xcodebuild readers+watchdog, subprocess run/timeout, lldb command timeout); static JSONDecoder in SimctlRunner; documented+suppressed the unavoidable @unchecked Sendable on SendableAXUIElement.

Deferred: 60 uppercaseAcronymsInIdentifiers lint warnings (bundleId/udid etc.) — pervasive public API names; renaming is a coordinated breaking change, out of scope.

Verification: swift build (build_tests) succeeded; 50 affected tests pass (Xctrace, XcodebuildCompletion, SubprocessTimeout, WaitForProcessExit, InteractSettle). No non-acronym lint warnings remain in Runners/.
