---
# y04-t3c
title: mcp__xc-build__archive reports success but produces no .xcarchive on disk
status: completed
type: bug
priority: normal
created_at: 2026-06-03T19:34:42Z
updated_at: 2026-06-03T19:42:59Z
sync:
    github:
        issue_number: "385"
        synced_at: "2026-06-03T19:45:04Z"
---

Calling `mcp__xc-build__archive` with `archive_path=/tmp/thesis-beta-macos.xcarchive`, `platform=macOS`, `code_signing_allowed=true`, `errors_only=true` on Thesis (project=Thesis.xcodeproj, scheme=Standard) returns:

```
Archive succeeded for scheme 'Standard' (macOS) at /tmp/thesis-beta-macos.xcarchive

Build succeeded (7 warnings)
```

But `/tmp/thesis-beta-macos.xcarchive` does not exist. Searched `~/Library/Developer/Xcode/Archives`, `~/Library/Developer/Xcode/DerivedData/**/ArchiveIntermediates`, `/tmp`, `/private/tmp`, `/var/folders`, and the project working directory — no `.xcarchive` created within 30 min of the call.

Reproduced twice with two different paths (`/tmp/thesis-beta-macos.xcarchive` and `/tmp/thesis-beta-macos-v2.xcarchive`). Same outcome both times.

Steps:
1. `mcp__xc-build__set_session_defaults project_path=Thesis.xcodeproj scheme=Standard`
2. `mcp__xc-build__archive archive_path=/tmp/thesis-beta-macos.xcarchive platform=macOS code_signing_allowed=true errors_only=true`
3. Tool reports 'Archive succeeded …'
4. `ls /tmp/thesis-beta-macos.xcarchive` → No such file or directory

Discovered while trying to produce a Distribution-signed macOS archive locally for the Thesis project (parent context: wsh-6kg, XCC's own export step fails and we wanted to ship via Transporter from a real local archive). Worked around by directing the user to Xcode GUI Product → Archive instead.

Expected: archive bundle materializes at the requested `archive_path`, with `Info.plist` containing `ApplicationProperties` and `Products/Applications/<app>.app` signed by a real Distribution identity. Direct shell invocation of the underlying archive command does produce the bundle, so the gap is in xc-mcp's archive tool path-handling or success detection (possibly reporting success based on a non-archive exit, or running with a tmpdir that gets cleaned up).

Context for repro: Xcode 26.2.0 / Xcode 26.5 toolchain on macOS 26.5. Standard scheme archives Release config, which has `PRODUCT_BUNDLE_IDENTIFIER=com.thesisapp.beta`, `CODE_SIGN_STYLE=Automatic`, `DEVELOPMENT_TEAM=D6GX9PC3SR`, `INSTALL_PATH=$(LOCAL_APPS_DIR)`. Local machine has a Distribution cert + cloud-managed profile available.



## Summary of Changes

Root cause: `xcodebuild archive` runs in two phases — build, then install/codesign + bundle write. xcodebuild prints `Build succeeded in …` / `** BUILD SUCCEEDED **` when the build phase finishes, *before* the install phase writes the .xcarchive bundle. If install/codesign takes >30 s with no stdout output (e.g. real Distribution signing with cloud-managed profiles), `XcodebuildRunner`'s no-output watchdog fires, sees a "build finished" marker in the buffer, throws `XcodebuildError.completedPipesHeldOpen` (added in qbz-ek1), and returns exit code 0 with a "success" status. `ArchiveTool` then formats `Archive succeeded …` — but xcodebuild was SIGKILL'd mid-install, so no .xcarchive bundle was ever written.

Fixes:

1. **`Sources/Core/XcodebuildRunner.swift`** — `outputShowsBuildFinished(_:arguments:)` now takes the xcodebuild argv. When `archive` is in the args, only archive-specific markers (`** ARCHIVE SUCCEEDED/FAILED **`, `Archive succeeded in …`, `Archive failed after …`) count as terminal. The build-phase markers no longer short-circuit the install phase. Generic builds still recognise build/test/clean markers as before, plus the new archive markers (so a `clean archive` or `build archive` invocation is still handled). `exitCode(forFinishedOutput:)` recognises the archive failure markers as well.
2. **`Sources/Tools/MacOS/ArchiveTool.swift`** — after `checkBuildSuccess`, verify the .xcarchive bundle actually exists at `archive_path`. If it does not, throw `MCPError.internalError` with a clear diagnostic ("xcodebuild reported archive success … but no .xcarchive bundle was created … retry with a larger timeout") instead of returning a misleading "Archive succeeded" message. Defense in depth: catches the symptom regardless of root cause.
3. **`Tests/XcodebuildCompletionDetectionTests.swift`** — added two tests covering the action-aware behaviour: `Build succeeded in …` and `** BUILD SUCCEEDED **` are not terminal when archive is the action; archive failure markers are terminal and derive exit code 65. All 8 tests in the suite pass (`swift test --filter XcodebuildCompletionDetectionTests`).

Verified: `swift build` succeeds; new tests pass. Cannot reproduce the original symptom end-to-end without a long signing pause, but the file-existence check guarantees the misleading "succeeded with no bundle" outcome can no longer occur.
