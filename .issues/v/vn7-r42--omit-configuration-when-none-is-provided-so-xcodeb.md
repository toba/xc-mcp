---
# vn7-r42
title: Omit -configuration when none is provided so xcodebuild honors the scheme's configuration
status: completed
type: bug
priority: normal
created_at: 2026-07-09T15:36:41Z
updated_at: 2026-07-09T15:48:39Z
sync:
    github:
        issue_number: "424"
        synced_at: "2026-07-09T15:51:57Z"
---

xc-mcp unconditionally injects `-configuration Debug` into every xcodebuild invocation when the caller provides no configuration argument and no session default is set. This overrides the scheme's own Build/Run action configuration, producing the wrong build settings — including bundle identifier and derived app path — for any scheme whose action uses a non-Debug configuration (Release or a custom configuration).

## Evidence

- `Sources/Core/Runners/XcodebuildRunner.swift`: `build()` (line ~360/376), `buildTarget()`, `test()`, `clean()`, `showBuildSettings()` all declare `configuration: String = "Debug"` and unconditionally append `["-configuration", configuration]` to the args.
- `Sources/Core/Session/SessionManager.swift:468` `resolveConfiguration(from:default:)` returns `arguments.getString("configuration") ?? configuration ?? defaultValue` where `defaultValue` is `"Debug"` — so with no arg and no session default, callers get "Debug" rather than "no configuration".

Net effect: `build_macos`, `test_macos`, `get_mac_app_path`, `get_app_bundle_id`, `show_build_settings`, `clean`, `archive`, and any other tool routing through these runners will report/build against Debug even when the scheme selects a different configuration.

## Source

Mirrors upstream getsentry/XcodeBuildMCP fix `623db7a` (PR #460, "Omit -configuration when none is provided", fixes their #443). Surfaced via `/cite review` on 2026-07-09.

## Proposed fix

- Make configuration optional throughout the runner chain (`configuration: String? = nil`) and only append `["-configuration", configuration]` when non-nil, so xcodebuild honors the scheme's Run/Build action configuration.
- Change `resolveConfiguration` (or add an optional variant) to return `nil` when neither an argument nor a session default is present, instead of falling back to "Debug".
- Audit each call site to ensure passing `nil` is threaded through rather than re-defaulting to "Debug".

## Tasks

- [x] Make `configuration` optional in XcodebuildRunner methods; conditionally append the flag
- [x] Add/adjust an optional configuration resolver in SessionManager that returns nil when unset
- [x] Update build/test/app-path/clean/archive/show-settings tools to pass through the optional value
- [x] Add a regression test: a scheme with a non-Debug Run action configuration yields settings/app-path for that configuration when no configuration is passed

## Summary of Changes

Made the build configuration optional throughout the xcodebuild-invoking path so `-configuration` is omitted when the user specifies no configuration (no argument, no session default), letting xcodebuild honor the scheme's own Build/Run/Test action configuration.

- `SessionManager.resolveConfiguration(from:)` now returns `String?` (nil when unspecified); dropped the "Debug" fallback and the `default:` parameter.
- `XcodebuildRunner.build/buildTarget/test/clean/showBuildSettings`: `configuration` is now `String? = nil` and `-configuration` is appended only when non-nil.
- Threaded the optional through shared helpers: `BuildSettingExtractor.validateMacOSSupport`, `DerivedDataLocator.findProjectRoot`, `TestToolHelper.runAndFormat`, and `ShowBuildDependencyGraphTool.fetchAllTargetSettings`.
- Removed duplicated inline "Debug"-defaulting config blocks in `GetAppBundleIdTool`, `GetMacBundleIdTool`, `GetMacAppPathTool` — they now use `resolveConfiguration`. `AnalyzeAppBundleTool` no longer defaults to "Release". Display strings render "scheme default" when unspecified.

Out of scope by design: `DiffBuildSettingsTool` (explicit Debug-vs-Release comparison), `PreviewCaptureTool` (internal injected host target), `ArchiveTool` (archive's conventional Release default), and XcodeProj-based project-file tools (named .pbxproj configs, not xcodebuild -configuration).

Regression coverage: 3 tests added to `SessionManagerPersistenceTests`. Affected suites pass. Mirrors upstream getsentry/XcodeBuildMCP 623db7a (PR #460).
