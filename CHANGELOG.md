# Changelog

## Week of Feb 22 – Feb 28, 2026

### ✨ Features

- Migrate from Foundation `Process` to `swift-subprocess`; safer process I/O; no more pipe deadlocks by design (#101)
- Add `validate_project` tool; catches stale embeds, missing links, and orphaned build phases before they bite you (#135)
- Add project configuration generation tools; create and modify test plans and schemes programmatically (#102)
- Add crash report search/inspect tool; dig through `~/Library/Logs/DiagnosticReports` without opening Console.app (#127)
- Add `check_build` tool for single-target compilation; type-check one target without rebuilding the world (#126)
- Debug tools now check process state before sending commands; no more mysterious hangs on crashed processes (#133)
- `build_debug_macos` detects early process crashes (`dyld`, `SIGABRT`) instead of silently hanging (#132)
- `test_macos` surfaces crash diagnostics when the test host fails to bootstrap (#100)
- Add test plan management tools to `xc-project`; create, query, and modify `.xctestplan` files (#122)
- Improve UI test and test plan ergonomics; less boilerplate, more doing (#121)
- Validate `only_testing` identifiers before running `xcodebuild`; catch typos before a 2-minute build (#118)
- Suppress non-project warnings in build output; see your warnings, not Apple's (#98)
- Add in-place target renaming with cross-reference updates (#117)
- `xc-swift` auto-detects `package_path` from working directory; one less thing to specify (#99)
- Add `--build-tests` flag to `swift_package_build` (#113)
- Add environment variable and skip filter support to `swift_package_test` (#112)
- Add `swift_format` and `swift_lint` tools to `xc-swift` server (#95)
- Register `test_sim` in the Build server so you don't need a separate simulator server (#97)
- Support `XCLocalSwiftPackageReference` deletion via XcodeProj 9.9.0 (#108)

### 🐞 Fixes

- Fix pipe deadlock; drain stdout/stderr before `waitUntilExit`; was causing intermittent server hangs (#119)
- Fix `xcodebuild` process not killed on MCP cancellation; orphaned builds no more (#104)
- Fix `build_debug_macos` falsely reporting crash on successful launch (#137)
- Fix process interrupt via `debug_lldb_command` racing with async stop notification (#136)
- Reload shared session file on access so focused servers stay in sync (#138)
- Fix `debug_stack` thread backtrace syntax (#131)
- Fix `stop_mac_app` hanging when process is crashed or under LLDB (#130)
- `test_macos` no longer reports success when `only_testing` filter matches zero tests (#129)
- Use parsed build output status instead of exit code alone; catches builds that "succeed" with errors (#115)
- Fix `list_files` missing files from synchronized folder targets (#106)
- Fix `list_test_plan_targets` failing on relative project paths (#120)
- Fix `search_crash_reports` requiring `process_name` or `bundle_id` when neither should be mandatory (#123)
- Add timeout support to `SwiftRunner`; prevents runaway swift commands (#125)

### 🗜️ Tweaks

- Redesign integration tests for speed; split slow tests behind `RUN_SLOW_TESTS` flag (#96)

## Week of Feb 15 – Feb 21, 2026

### ✨ Features

- Add `build_debug_macos`; launch macOS apps under LLDB, the way Xcode's Run button does (#4)
- Add 8 new LLDB debug tools; watchpoints, memory reads, symbol lookup, view hierarchy dumps, and more (#1)
- Add `interact_` tools for macOS app UI interaction via Accessibility API; click, type, inspect UI trees (#60)
- Add `screenshot_mac_window` tool; capture any window via ScreenCaptureKit without needing a simulator (#58)
- SwiftUI preview capture tool; render `#Preview` macros to images on a simulator (#59)
- Add macOS log capture tools; stream and filter unified logs per-app (#8)
- Share session defaults across MCP servers; set once, use everywhere (#32)
- Add `rename_target` tool with cross-reference updates across schemes, dependencies, and build phases (#111)
- Add `remove_group`, `remove_target_from_synchronized_folder`, and exception set tools (#103, #128, #107)
- Add tool to share existing synchronized folder with another target (#72)
- Improve `test_macos` ergonomics; timeout parameter, better error surfacing from xcresults (#109)
- Doctor, gesture presets, Xcode state sync, next-step hints, and workflow management; a batch of quality-of-life tools (#81)

### 🐞 Fixes

- Fix LLDB sessions hanging; switch from pipes to PTY for stdin, matching how real terminals work (#33)
- Fix debug tools hanging due to ephemeral LLDB sessions that vanish mid-command (#11)
- Fix `build_debug_macos` `SIGABRT` crash; launch via Launch Services instead of direct LLDB process launch (#9)
- Fix `build_debug_macos` producing no useful error on failure (#38)
- Fix `debug_attach_sim` and `debug_breakpoint_add` hanging on macOS native apps (#27)
- Fix `preview_capture` compiler crash from `#Preview` in additional source files (#63)
- Fix `preview_capture` build config to avoid `ASTMangler` crash and launch failure (#62)
- Fix `preview_capture` for local Swift packages missing deployment target (#71)
- Fix `add_target` setting wrong bundle identifier key (#79)
- Fix `add_target` missing `productReference` and Products group entry (#80)
- Fix `add_framework` creating duplicate file references instead of reusing `BUILT_PRODUCTS_DIR` (#73, #74)
- Fix `list_files` to include synchronized folder contributions (#105)
- Fix `rename_target` gaps found during real-world module rename (#110)
- Fix `test_macos` error output truncation (#78)
- Surface warning when `testmanagerd` crashes during test run (#77)
- Fix `swift-frontend` SILGen crash when building IceCubesApp fixture (#65, #64)
- Fix IceCubesApp full build crash with Xcode 26 (#70)
- Fix Alamofire fixture build with Xcode 26 (#69)
- Fix `buildRunScreenshot` installing wrong platform build (#68)
- Fix integration test failures for `preview_capture` and IceCubesApp (#67, #66, #91)
- Fix reading test stdout from XCUI tests (#76)

### 🗜️ Tweaks

- Extract `ProcessRunner`, `ProcessKiller`, `LogCaptureBuilder`, and `BuildSettingExtractor` utilities; less duplication, cleaner tool code (#88, #84, #82)
- Migrate manual argument extraction to `ArgumentExtraction` helpers (#89)
- Replace `DispatchQueue` usage with structured concurrency (#83)
- Replace `Date()` timing with `ContinuousClock` (#86)
- Add typed throws to `XCStringsParser` mutation methods (#90)
- Deduplicate batch `parseEntries` in XCStrings tools (#85)
- Add `reserveCapacity` to batch array loops (#87)
- Extract shared `findSyncGroup` and clean up sync folder tools (#116)
- Expose 6 implemented-but-unregistered project tools (#124)
- Fix `preview_capture` end-to-end rendering (#61)
- Fix `PreviewCaptureTool` swiftlint warnings (#92)

## Week of Feb 1 – Feb 7, 2026

### 🗜️ Tweaks

- Review xcsift coverage scanner optimization (#2)
- Review xcsift Swift Testing PR (#14)
- Review xcsift issue-52 fix (#34)
- Review xcstrings-crud `BatchWriteResult` fix (#39)

## Week of Jan 25 – Jan 31, 2026

### ✨ Features

- Integrate xcsift build output parsing; structured errors, warnings, and notes instead of raw `xcodebuild` noise (#17)
- Add granular test selection to test tools; run specific test classes or methods (#30)
- Add code coverage collection to test tools (#44)
- Add Copy Files build phase management; embed frameworks, copy resources, all the fun stuff (#23)
- Add `remove_synchronized_folder` tool (#12)

### 🐞 Fixes

- Fix MCP tools corrupting unrelated `PBXCopyFilesBuildPhase` sections; the worst kind of silent data loss (#29)
- Fix `set_build_setting` dropping `dstSubfolder` fields from `PBXCopyFilesBuildPhase` (#31)
- Fix `add_synchronized_folder` deleting scheme files on save (#24)
- Fix synchronized folder path handling for nested groups (#6)
- Fix scheme deletion; use `writePBXProj` instead of `write` to preserve `.xcscheme` files (#40)

### 🗜️ Tweaks

- Eliminate ~100 duplicate files across focused servers (#25)
- Implement review consolidation changes (#20)

## Week of Jan 18 – Jan 24, 2026

### ✨ Features

- Implement Homebrew package; `brew install toba/tap/xc-mcp` and you're off (#42)
- Add `--no-sandbox` flag to `xc-project`, `xc-build`, and `xc-strings` servers (#13)
- Integrate xcstrings-crud as the `xc-strings` MCP server; full localization string catalog management (#43)
- Improve MCP tool timeout handling with streaming progress; no more silent hangs on long builds (#16)
- Error handling improvements across all tools (#37)

### 🗜️ Tweaks

- Split `xc-mcp` into 7 focused MCP servers; smaller token footprint, faster client setup (#5)
- Complete all 11 implementation phases: Foundation, Simulator, Device, macOS Build, Discovery, Log Capture, Simulator Extended, LLDB Debugging, UI Automation, Swift Package Manager, Utilities (#52 through #50)
- Migrate tests to Swift Testing framework with parameterized test cases (#10)
- Add typed throws to select methods (#7)
- Refactor `NSString` path manipulation to `URL` (#3)
- Add DocC documentation (#41)
- Add XCStrings test coverage (#36)
- Clean up unused files and update README (#28)
- Create Swift code review skill (#26)
- Code optimization pass (#45)
- Fix swiftlint warnings (#22)
- Document unexposed capabilities (#15)
- Unified Xcode MCP Server milestone completed (#19)
