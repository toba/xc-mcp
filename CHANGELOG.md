# Changelog

## Week of Apr 26 – May 2, 2026

### ✨ Features

- Auto-scope `xcodebuild` `-derivedDataPath` to `~/Library/Caches/xc-mcp/DerivedData/<Project>-<hash>`; prevents concurrent build collisions when multiple xc-mcp sessions target the same clone; opt-out via `XC_MCP_DISABLE_DERIVED_DATA_SCOPING` ([#289](https://github.com/toba/xc-mcp/issues/289))
- Add `toggle_software_keyboard` / `toggle_hardware_keyboard` simulator tools; toggle the simulator's on-screen keyboard via Cmd+K / Cmd+Shift+K through AppleScript ([#293](https://github.com/toba/xc-mcp/issues/293))
- Surface slowest passing tests in test output via `XC_MCP_SHOW_TEST_TIMING`; previously hidden when total > 50 with failures ([#291](https://github.com/toba/xc-mcp/issues/291))
- Pre-warm SwiftPM cache on `set_session_defaults`; spawn a background `swift build --build-tests` when the cache is cold; auto-cancel when the user runs `swift_package_*`; opt-out via `XC_MCP_DISABLE_WARMUP`; status visible in `show_session_defaults` ([#296](https://github.com/toba/xc-mcp/issues/296))

### 🐞 Fixes

- Expand leading `~` in user-supplied paths; `set_session_defaults` and per-call `project_path` / `workspace_path` / `package_path` arguments now resolve `~/Developer/foo.xcodeproj` correctly ([#292](https://github.com/toba/xc-mcp/issues/292))
- Prevent MCP server disconnect when cancelling a long-running build/test; spawn child processes in their own process group and `SIGKILL` the whole group on cancel so SPM build plugins and grandchildren release the stdout/stderr pipes ([#294](https://github.com/toba/xc-mcp/issues/294))
- `swift_package_test` / `swift_package_build` no longer abort after 5min on a cold cache; auto-extend timeout to 15min when `.build/checkouts` is empty; timeout errors now include the package path and a cold-cache hint ([#295](https://github.com/toba/xc-mcp/issues/295))

### 🗜️ Tweaks

- Review XcodeBuildMCP commits for features to incorporate ([#290](https://github.com/toba/xc-mcp/issues/290))

## Week of Apr 19 – Apr 25, 2026

### ✨ Features

- Surface verbose compiler output on signal crashes; `swift_package_build` and `swift_diagnostics` auto-retry with `-v` to identify the crashing file and compiler backtrace ([#283](https://github.com/toba/xc-mcp/issues/283))
- Add `remove_run_script_phase` tool; remove `PBXShellScriptBuildPhase` build phases from a target by name; refuses to remove ambiguous matches; cleans up orphaned build files ([#284](https://github.com/toba/xc-mcp/issues/284))

### 🐞 Fixes

- `add_package_product`: detect SPM plugin products from local `Package.swift` and skip the Frameworks build phase; add `kind` parameter (`auto` | `library` | `plugin`) for explicit override ([#287](https://github.com/toba/xc-mcp/issues/287))
- `add_package_product`: wire the `package` field on `XCSwiftPackageProductDependency` for products not yet linked to any target; add `package_url` / `package_path` parameters; discover owning package via local `Package.swift` checkouts ([#288](https://github.com/toba/xc-mcp/issues/288))

### 🗜️ Tweaks

- Add `swiftiomatic-plugins` build-tool plugin for self-hosted lint-on-build; apply to `XCMCPCore`, `XCMCPTools`, and the `xc-mcp` executable ([#285](https://github.com/toba/xc-mcp/issues/285))

## Week of Apr 12 – Apr 18, 2026

### ✨ Features

- Add 9 Icon Composer tools (`create_icon`, `export_icon`, `read_icon`, `add_icon_layer`, `remove_icon_layer`, `set_icon_fill`, `set_icon_effects`, `set_icon_layer_position`, `set_icon_appearances`); full `.icon` bundle creation and editing with `IconManifest` Codable model ([#278](https://github.com/toba/xc-mcp/issues/278))
- Handle Xcode 26 objectVersion 100 project format; update default from 56 to 77 with configurable `object_version` parameter; add post-migration validation checks to `validate_project`; add `repair_project` tool for fixing null build files and orphaned entries ([#282](https://github.com/toba/xc-mcp/issues/282))

### 🐛 Fixes

- Fix `screenshot_mac_window` hanging for 20+ seconds; replace ScreenCaptureKit with `CGWindowListCopyWindowInfo` + `screencapture -l` ([#275](https://github.com/toba/xc-mcp/issues/275))
- Fix `PreviewCaptureTool` `captureMacOSWindow` same ScreenCaptureKit hang; extract shared `WindowCapture` helper to Core ([#274](https://github.com/toba/xc-mcp/issues/274))
- Fix `add_file` missing `lastKnownFileType` for `.xcassets`; fix scaffold tools not wiring source files or asset catalog into Xcode project build phases; fix AppIcon `Contents.json` missing `scale` field ([#276](https://github.com/toba/xc-mcp/issues/276))
- Fix `add_file` silently dropping `PBXBuildFile` when build phase `files` is nil; affects resources, sources, and headers phases in real Xcode projects ([#277](https://github.com/toba/xc-mcp/issues/277))
- Fix `add_file` missing `lastKnownFileType` for `.icon` files; fix path resolution for files above `.xcodeproj` but within repo root ([#278](https://github.com/toba/xc-mcp/issues/278))
- Fix scaffold `AppIcon.appiconset/Contents.json` using invalid `"platform": "macos"` value; `actool` silently skips the icon ([#279](https://github.com/toba/xc-mcp/issues/279))

### 🗜️ Tweaks

- Bump XcodeProj to 9.11.0; add `debug_as_which_user` parameter to `create_scheme` for `debugAsWhichUser` on `LaunchAction`
- `export_icon` now returns inline base64 PNG image so the LLM client can see the rendered icon

## Week of Apr 5 – Apr 11, 2026

### ✨ Features

- Add ReportCrash throttle detection to `search_crash_reports`; warn when macOS stops generating `.ips` files after ~25 reports per process and list other processes with reports in the time window ([#259](https://github.com/toba/xc-mcp/issues/259))
- Add memory diagnostic tools (`memory_leaks`, `memory_heap`, `memory_vmmap`, `memory_stringdups`, `memory_malloc_history`); wrap Xcode's hidden CLI tools for process memory analysis ([#265](https://github.com/toba/xc-mcp/issues/265))
- Add `symbolicate_address` tool; batch crash address symbolication via `atos` ([#266](https://github.com/toba/xc-mcp/issues/266))
- Add `version_management` tool; read/set marketing version and build numbers via `agvtool` ([#262](https://github.com/toba/xc-mcp/issues/262))
- Add `notarize` tool; full macOS notarization workflow via `notarytool` and `stapler` ([#263](https://github.com/toba/xc-mcp/issues/263))
- Add `validate_asset_catalog` tool; pre-build `.xcassets` validation via `actool` ([#264](https://github.com/toba/xc-mcp/issues/264))
- Add `open_in_xcode` tool; open files at specific lines, projects, or workspaces via `xed` ([#267](https://github.com/toba/xc-mcp/issues/267))
- Add 6 build diagnostics tools (`check_output_file_map`, `extract_crash_traces`, `list_build_phase_status`, `read_serialized_diagnostics`, `diff_build_settings`, `show_build_dependency_graph`); debug silent compilation failures by inspecting OutputFileMap entries, compiler crash traces, build phase status, `.dia` files, build setting diffs, and dependency graphs ([#268](https://github.com/toba/xc-mcp/issues/268))

### 🐛 Fixes

- Fix `swift_package_build` crashing on large projects; stream subprocess output with tail-truncation instead of throwing on overflow; reduce default output limit from 10MB to 2MB ([#272](https://github.com/toba/xc-mcp/issues/272))
- Fix multi-suite test count bug in `BuildOutputParser`; accumulate XCTest bundle counts, Swift Testing run counts, and parallel scheduling totals instead of overwriting ([#261](https://github.com/toba/xc-mcp/issues/261))
- Fix `add_framework` silently ignoring `embed: true` for developer frameworks (XcodeKit, XCTest); fix `add_to_copy_files_phase` not auto-defaulting `CodeSignOnCopy`/`RemoveHeadersOnCopy` for phases with `dstSubfolderSpec == .frameworks` ([#270](https://github.com/toba/xc-mcp/issues/270))
- Fix `add_app_extension` using wrong product type for Xcode extensions; add `source_editor` extension type mapping to `com.apple.product-type.xcode-extension`; add `.xcodeExtension` to `remove_app_extension` valid types ([#271](https://github.com/toba/xc-mcp/issues/271))
- Fix `swift_package_test` truncating failure messages; capture all `↳` continuation lines instead of only the first; preserve parameterized test argument values (`→ value`) in test name ([#273](https://github.com/toba/xc-mcp/issues/273))

### 🗜️ Tweaks

- Fix `BuildOutputParser` Swift Testing edge cases; handle `(aka '...')` verbose suffix, `with N test cases` parameterized results, and `recorded an issue with N argument values` parameterized issues; add 7 golden-file snapshot tests for `BuildResultFormatter` ([#269](https://github.com/toba/xc-mcp/issues/269))

## Week of Mar 29 – Apr 4, 2026

### ✨ Features

- Add `remove_package_product` and `list_package_products` tools; remove individual SPM product dependencies from targets and inspect per-target product linkage ([#247](https://github.com/toba/xc-mcp/issues/247))
- `add_target_to_test_plan`: support `selectedTests` filtering with `xctest_classes` and `suites` parameters; restrict test plan entries to specific classes, methods, or Swift Testing functions ([#252](https://github.com/toba/xc-mcp/issues/252))
- `move_file` now updates synchronized folder exception sets; renaming a file that appears in `membershipExceptions` no longer requires manual remove/add workaround ([#254](https://github.com/toba/xc-mcp/issues/254))

### 🐞 Fixes

- Fix `remove_package_product` corrupting pbxproj; clean up `PBXTargetDependency` entries with `productRef` created by Xcode GUI ([#248](https://github.com/toba/xc-mcp/issues/248))
- Fix `add_framework` creating bogus `.framework` file reference for static libraries (`.a`); reuse existing product reference or create proper `archive.ar` entry in `BUILT_PRODUCTS_DIR` ([#250](https://github.com/toba/xc-mcp/issues/250))
- Fix `test_macos` `only_testing` filter failing for Swift Testing backtick-escaped single-word method names; auto-wrap Swift keywords like `class` and `import` in backticks ([#251](https://github.com/toba/xc-mcp/issues/251))
- Fix `build_macos` suppressing all compiler warnings; add `show_warnings` parameter to list project-local warnings on successful builds ([#238](https://github.com/toba/xc-mcp/issues/238))
- Fix synchronized folder exception tools corrupting pbxproj; use text-based `PBXProjTextEditor` instead of XcodeProj round-trip serializer ([#256](https://github.com/toba/xc-mcp/issues/256))
- Fix `add_framework` silently failing to add local product frameworks; detect existing `BUILT_PRODUCTS_DIR` references before classifying bare names as system frameworks
- Fix `add_framework` creating stale `PBXFileReference` for cross-project framework products; reuse existing `PBXReferenceProxy` entries instead of creating unresolvable group-relative references

### 🗜️ Tweaks

- Remove unnecessary `@unchecked Sendable` from `BuildOutputParser`; replace `[String: Any]` JSON parsing with `Decodable` models in `XCResultParser` and `CrashReportParser`; fix 21 swiftlint warnings

## Week of Mar 22 – Mar 28, 2026

### ✨ Features

- Support project-level build settings in `set_build_setting`; omit `target_name` to apply settings at the project level instead of a specific target
- Add `build_settings` parameter to all build/test tools; pass xcodebuild build setting overrides (e.g. `SWIFT_ENABLE_EXPLICIT_MODULES=NO`) as highest-precedence positional arguments ([#243](https://github.com/toba/xc-mcp/issues/243))
- Add MCP tool annotations to all 197 tools; explicit `readOnlyHint`/`destructiveHint`/`openWorldHint` so clients can auto-approve safe operations ([#244](https://github.com/toba/xc-mcp/issues/244))
- Add `timeout` parameter to `build_macos` and `build_run_macos` tools; return partial diagnostics on timeout instead of an empty error ([#245](https://github.com/toba/xc-mcp/issues/245))

### 🐞 Fixes

- Fix `add_swift_package` crashing with SIGTRAP on projects with sub-project references; work around XcodeProj `sortProjectReferences` force-unwrap of nil `PBXFileElement.name` by backfilling from `path`
- Fix `remove_target` leaving orphaned `PBXContainerItemProxy` and `PBXTargetDependency` entries in pbxproj; also search all target types instead of only native targets ([#237](https://github.com/toba/xc-mcp/issues/237))
- Fix `PluralVariation` and `DeviceVariation` field types to match xcstrings JSON format; add `VariationValue` wrapper for correct decoding of plural/device variations ([#239](https://github.com/toba/xc-mcp/issues/239))
- Fix device log capture requiring sudo; switch from `log collect --device-udid` to `log stream` background process ([#233](https://github.com/toba/xc-mcp/issues/233))
- Fix `list_files` misleading `membershipExceptions` label; fix `remove_synchronized_folder_exception` not finding auto-created exception sets; add `add_package_product` tool for linking existing SPM products to targets ([#227](https://github.com/toba/xc-mcp/issues/227))
- Fix `start_device_log_cap` unable to capture device logs; switch to `idevicesyslog` from libimobiledevice with CoreDevice-to-hardware UDID resolution ([#235](https://github.com/toba/xc-mcp/issues/235))
- Fix `stop_device_log_cap` failing to collect logs from physical devices; correct `log collect --start` date format from ISO8601 to `yyyy-MM-dd HH:mm:ss` ([#232](https://github.com/toba/xc-mcp/issues/232))
- Fix `remove_swift_package` leaving stale `PBXBuildFile` and `PBXSwiftPackageProductDependency` entries in pbxproj ([#234](https://github.com/toba/xc-mcp/issues/234))

### 🗜️ Tweaks

- Extract `TestToolHelper` to deduplicate test tool validation/bundle/formatting logic across `TestSimTool`, `TestMacOSTool`, `TestDeviceTool`; replace `[String: Any]` with `Decodable` types in `DeviceCtlRunner`; fix lint warnings in `BuildResultFormatter`, `StartDeviceLogCapTool`, `ScaffoldModuleTool`
- Upgrade to Swift 6.3, macOS 26, MCP SDK 0.12.0, `swift-subprocess` 0.4.0; migrate `TerminationStatus.unhandledException` to `.signaled`, `.combineWithOutput` to `.combinedWithOutput`, `.text` pattern matching to 3-element tuple
- Swift review fixes from 2026-03-21 changes ([#236](https://github.com/toba/xc-mcp/issues/236))

## Week of Mar 15 – Mar 21, 2026

### ✨ Features

- Add `show_mac_log` tool to query historical macOS unified logs via `log show`; filter by bundle ID, process name, subsystem, or custom predicate with configurable time range and tail lines ([#216](https://github.com/toba/xc-mcp/issues/216))
- Add `swift_symbols` tool to extract and query public APIs of Swift modules via `swift-symbolgraph-extract`; filter by name, symbol kind, and platform ([#217](https://github.com/toba/xc-mcp/issues/217))
- Investigate dead code detection tooling; evaluated Periphery alternatives and confirmed it as the best option ([#171](https://github.com/toba/xc-mcp/issues/171))
- Share session defaults across all focused MCP servers; `set_session_defaults` in one server applies everywhere ([#208](https://github.com/toba/xc-mcp/issues/208))
- Add `get_performance_metrics`, `set_performance_baseline`, and `show_performance_baselines` tools; extract `measure(metrics:)` results from xcresult bundles and create/update `.xcbaseline` plists for automatic regression detection ([#205](https://github.com/toba/xc-mcp/issues/205))
- Add `set_test_plan_skipped_tags` tool; add or remove `skippedTags` at plan-level or per-target in `.xctestplan` files ([#225](https://github.com/toba/xc-mcp/issues/225))
- `build_macos`: truncate cascade errors when root cause is a `PhaseScriptExecution` failure; collapse "Unable to find module dependency" noise into a single summary line ([#230](https://github.com/toba/xc-mcp/issues/230))
- `BuildGuard`: wait for build lock with 5-minute timeout instead of failing immediately; concurrent agents now queue instead of erroring ([#231](https://github.com/toba/xc-mcp/issues/231))

### 🐞 Fixes

- Fix `build_run_sim` false "build appears stuck" error; increase no-output timeout from 30s to 120s for simulator builds where linking/signing produces long output gaps; auto-boot shutdown simulators before install/launch ([#223](https://github.com/toba/xc-mcp/issues/223), [#222](https://github.com/toba/xc-mcp/issues/222))
- Fix `build_device` failing to find connected device by UDID; improve device lookup to match partial UDIDs ([#212](https://github.com/toba/xc-mcp/issues/212))
- Wait for process exit after SIGTERM in `swift_package_stop`, `LogCapture.stopCapture`, and `LLDBRunner.terminate()`; poll with `kill -0` and escalate to SIGKILL ([#221](https://github.com/toba/xc-mcp/issues/221))
- Fix `debug_evaluate` and `debug_lldb_command` returning empty output at breakpoints; drain stale PTY output before sending commands ([#226](https://github.com/toba/xc-mcp/issues/226))
- Fix `stop_mac_app` failing to kill debugger-attached processes in TX state; detach LLDB before sending SIGTERM/SIGKILL ([#224](https://github.com/toba/xc-mcp/issues/224))
- Fix `list_files` misleading `membershipExceptions` label; fix `remove_synchronized_folder_exception` not finding auto-created exception sets; add `add_package_product` tool for linking existing SPM products to targets ([#227](https://github.com/toba/xc-mcp/issues/227))
- Fix `test_macos` failing entire run when one `only_testing` target is invalid; pre-validate entries against available test targets and filter out invalid ones with a warning ([#229](https://github.com/toba/xc-mcp/issues/229))
- Fix `stop_device_log_cap` failing to collect logs from physical devices; correct `log collect --start` date format from ISO8601 to `yyyy-MM-dd HH:mm:ss`; surface error details when `log collect` writes diagnostics to stdout
- Fix device log capture requiring sudo; switch from `log collect --device-udid` to `log stream` background process ([#233](https://github.com/toba/xc-mcp/issues/233))
- Fix `remove_swift_package` leaving stale `PBXBuildFile` and `PBXSwiftPackageProductDependency` entries in pbxproj ([#234](https://github.com/toba/xc-mcp/issues/234))
- Fix `start_device_log_cap` unable to capture device logs; `log stream` has no device flags; switch to `idevicesyslog` from libimobiledevice with CoreDevice-to-hardware UDID resolution ([#235](https://github.com/toba/xc-mcp/issues/235))

### 🗜️ Tweaks

- Review XcodeBuildMCP v2.3.0 changes for applicability; no gaps in list-schemes or simulator init, confirmed SIGTERM fix needed ([#220](https://github.com/toba/xc-mcp/issues/220))
- Upgrade MCP Swift SDK from 0.10.2 to 0.11.0; adds 2025-11-25 spec coverage, icons/metadata, elicitation, HTTP transport ([#219](https://github.com/toba/xc-mcp/issues/219))

## Week of Mar 8 – Mar 14, 2026

### ✨ Features

- Add `show_performance_baselines` tool to xc-build; read and display existing `.xcbaseline` plists with human-readable metric names, filtering by target, test class, and metric type
- Add `get_performance_metrics` and `set_performance_baseline` tools to xc-build; extract `measure(metrics:)` results from xcresult bundles and create/update `.xcbaseline` plists for automatic regression detection
- `build_macos` / `test_macos`: add `errors_only` parameter to suppress warnings from output; show only compiler errors, linker errors, and build summary ([#195](https://github.com/toba/xc-mcp/issues/195))
- Add `sample_mac_app` and `profile_app_launch` profiling tools; extract `PIDResolver` to Core; parse sample output into agent-friendly summaries
- Integrate Swift Backtrace API (SE-0419); attach symbolicated backtraces to unexpected `MCPError.internalError` on macOS 26+
- Add `scaffold_module` composite tool; create a framework module with test target, sync folders, dependencies, embedding, and test plan entry in one call ([#177](https://github.com/toba/xc-mcp/issues/177))
- `create_scheme`: accept `build_targets` array for multiple build action entries; first target is primary for launch/test
- `detect_unused_code`: filter out Periphery's `superfluousIgnoreComment` warnings; these are an unresolvable cycle on assign-only properties with `// periphery:ignore` comments ([#198](https://github.com/toba/xc-mcp/issues/198))
- `build_macos`: add `for_testing` parameter to run `build-for-testing`; compiles test targets without executing them. `test_macos`/`test_sim`/`test_device`: add `test_plan` parameter to target non-default test plans. `list_test_plan_targets`: add `test_plan` and `all_plans` parameters to query plans not attached to a scheme
- `build_device` now returns the built `.app` path in its output; enables seamless `build_device` → `install_app_device` → `launch_app_device` pipeline
- Add `deploy_device` and `build_deploy_device` composite tools; stop → install → launch (or build → stop → install → launch) in a single call (bpv-4ka)

### 🐞 Fixes

- Fix `build_device` false "build appears stuck" error; increase no-output timeout from 30s to 120s for device builds where code signing produces long output gaps
- Fix `list_devices` showing "Type: Unknown" for iPad Mini; read `marketingName` from `hardwareProperties` instead of `deviceProperties`
- `build_macos` / `build_run_macos` / `test_macos` / `build_debug_macos` now reject iOS-only projects with a clear error instead of silently building; checks `SUPPORTED_PLATFORMS` and suggests xc-simulator tools
- Fix `add_synchronized_folder_exception` creating duplicate exception sets; append to existing set for the same target instead of creating a second one. Fix `remove_synchronized_folder_exception` only checking the first exception set for a target
- Fix `sample_mac_app` bundle ID lookup and output capture; use `NSRunningApplication` instead of `pgrep` and `-file` flag for reliable `sample` output
- Fix `detect_unused_code` `result_file` returning stale entries from prior scans
- Fix `test_macos` `only_testing` failing to match Swift Testing functions with backtick-escaped names containing spaces; auto-normalize identifiers by wrapping in backticks and appending `()`
- Fix `stop_app_device` failing with "Missing expected argument `--pid`"; resolve bundle identifier to PID via `devicectl device info processes` before terminating (cfo-jj0)
- Fix `start_device_log_cap` producing empty log files; replace nonexistent `devicectl device info syslog` with `log collect --device-udid` + `log show` collection-based approach (m5k-jma)

## Week of Mar 1 – Mar 7, 2026

### ✨ Features

- Add `detect_unused_code` tool wrapping Periphery CLI; finds unused declarations, redundant imports, assign-only properties, and redundant public accessibility in Swift projects ([#171](https://github.com/toba/xc-mcp/issues/171))
- `test_macos` now returns XCTest `measure()` timing data in results; average, relative standard deviation, and individual values ([#169](https://github.com/toba/xc-mcp/issues/169))
- `test_macos` now surfaces per-test results with skip reasons and performance metrics; no more "1 passed" when 2 tests were silently skipped ([#180](https://github.com/toba/xc-mcp/issues/180))
- `test_macos` error output now lists failed test names prominently; no more scanning 3600+ lines to find 4 failures ([#185](https://github.com/toba/xc-mcp/issues/185))
- `test_macos` output now always includes both passed and failed counts in the summary line; grep-friendly even with `-quiet` builds
- `search_crash_reports` now supports `report_path` for reading a specific crash report directly; agents can search → get path → read full report without re-searching ([#186](https://github.com/toba/xc-mcp/issues/186))
- `search_crash_reports` now shows symbolicated crashing thread stack trace; top 15 frames with image names, symbols, and source locations ([#182](https://github.com/toba/xc-mcp/issues/182))
- Add JSON output mode (`format: "json"`) and field selection (`fields`) to discovery tools; `show_build_settings`, `list_schemes`, `list_test_plan_targets`, `discover_projs` ([#163](https://github.com/toba/xc-mcp/issues/163))
- Add `get_coverage_report` and `get_file_coverage` tools; per-target and function-level coverage from xcresult bundles
- Add `validate_project` tool; catches dangling copy-files refs, orphaned build files, unreferenced phases, and inconsistent embedding ([#134](https://github.com/toba/xc-mcp/issues/134))
- Add `remove_framework` tool; remove framework dependencies from one or all targets, cleaning up link phases, embed phases, and orphaned file references ([#158](https://github.com/toba/xc-mcp/issues/158))
- `detect_unused_code`: add `group_by` parameter for per-target, per-kind, and per-directory summaries ([#188](https://github.com/toba/xc-mcp/issues/188))
- Add `sample_mac_app`, `profile_app_launch`, and `SampleOutputParser`; profiling and performance capture tools for xc-build with parsed call-stack summaries
- `sample_mac_app` parses raw `sample` output into agent-friendly summaries; heaviest functions table, call paths, idle thread filtering
- Integrate Swift Backtrace API (SE-0419); attach symbolicated backtraces to unexpected `MCPError.internalError` on macOS 26+ ([#184](https://github.com/toba/xc-mcp/issues/184))

### 🐞 Fixes

- Fix `detect_unused_code` checklist format exceeding MCP token limit on large projects; replace separate checklist mode with always-on disk checklist and compact summary output ([#183](https://github.com/toba/xc-mcp/issues/183))
- Fix `test_macos` false-positive stuck timeout on XCUI performance tests; increase default no-output timeout from 30s to 120s for test commands ([#178](https://github.com/toba/xc-mcp/issues/178))
- Fix `list_test_plan_targets` returning "no test plans found" for schemes with inline test targets; falls back to scheme `<TestAction>` testable references ([#179](https://github.com/toba/xc-mcp/issues/179))
- Document `only_testing` method-level filter limitation for XCUI test targets; xcodebuild silently runs 0 tests; suggest class-level filtering in error message ([#181](https://github.com/toba/xc-mcp/issues/181))
- Fix subprocess orphan processes on MCP abort/timeout; configure `teardownSequence` (SIGTERM → 5s → SIGKILL) so cancelled builds/tests don't hold the SPM lock ([#171](https://github.com/toba/xc-mcp/issues/171))
- Fix `validate_project` crash from `PBXBuildFile` Hashable violation; use `ObjectIdentifier` instead of `Set<PBXBuildFile>`
- Fix `formatTestToolResult` exit-code override suppressing failures when no tests ran; guard with `totalTestCount > 0` ([#166](https://github.com/toba/xc-mcp/issues/166))
- Fix `swift_package_test` reporting passing tests as MCP error -32603; override non-zero exit code when parsed output confirms all tests passed ([#160](https://github.com/toba/xc-mcp/issues/160))
- Fix `add_file` creating duplicate `PBXFileReference` entries and miscomputing paths for groups with a `path` property; uses `sourceRoot` when file is outside the group's resolved path, deduplicates existing refs ([#159](https://github.com/toba/xc-mcp/issues/159))
- Fix `remove_file` removing files from all targets when multiple targets have files with the same name; now matches by full path via `fullPath(sourceRoot:)` instead of filename ([#156](https://github.com/toba/xc-mcp/issues/156))
- Fix `add_swift_package` returning "already exists" instead of linking product to a new target; now links the product and detects duplicates ([#154](https://github.com/toba/xc-mcp/issues/154))
- Fix `start_mac_log_cap` process name derivation; resolve actual executable name from app bundle `Info.plist` instead of lowercased bundle ID suffix; case-insensitive fallback when bundle not found ([#186](https://github.com/toba/xc-mcp/issues/186))
- Fix `detect_unused_code` `result_file` returning stale entries from prior scans; delete old checklist when a new scan overwrites the cache file
- Fix `detect_unused_code` checklist not reconciling with already-removed code; strengthen agent instructions to mark items done immediately after each resolution ([#187](https://github.com/toba/xc-mcp/issues/187))
- Fix `add_file` path doubling when adding files to groups with a filesystem `path`; file reference now computed relative to the group location ([#155](https://github.com/toba/xc-mcp/issues/155))
- Default `ONLY_ACTIVE_ARCH=YES` for Debug in all target-creation tools; prevents cross-compilation failures with SPM dependencies ([#151](https://github.com/toba/xc-mcp/issues/151))
- Fix `add_target`, `add_app_extension`, `add_swift_package`, `add_framework`, and `create_xcodeproj` issues found during extension setup; orphan targets, missing framework linking, wrong `sourceTree` for developer frameworks, macOS `TARGETED_DEVICE_FAMILY`, `ALWAYS_SEARCH_USER_PATHS` ([#150](https://github.com/toba/xc-mcp/issues/150))
- Fix `add_target` only creating Debug/Release configs; now matches all project-level build configurations ([#176](https://github.com/toba/xc-mcp/issues/176))
- Fix `add_target` creating groups at project root; add `parent_group` parameter for nesting under existing groups ([#174](https://github.com/toba/xc-mcp/issues/174))
- Fix `add_target` adding extraneous build settings; minimize to `PRODUCT_BUNDLE_IDENTIFIER`, `PRODUCT_NAME`, `GENERATE_INFOPLIST_FILE` ([#173](https://github.com/toba/xc-mcp/issues/173))
- Fix `add_to_copy_files_phase` missing `CodeSignOnCopy`/`RemoveHeadersOnCopy` attributes; add `attributes` parameter with auto-defaults for Embed Frameworks ([#175](https://github.com/toba/xc-mcp/issues/175))
- Fix `add_file` rejecting slash-separated group paths like `Components/TableView`; unify group path resolution across all tools ([#172](https://github.com/toba/xc-mcp/issues/172))
- Fix `sample_mac_app` failing for apps with spaces/parens in name; use `NSRunningApplication` for bundle ID lookup and `-file` flag for reliable `sample` output capture

### 🗜️ Tweaks

- Isolate session defaults by PPID so parallel MCP clients don't clobber each other
- Enhance test plan error hints with scheme awareness; suggests the correct scheme when a test target isn't in the specified scheme
- Trim verbose tool descriptions; reduce token overhead for 7 tools ([#163](https://github.com/toba/xc-mcp/issues/163))
- Evaluate MCP vs CLI architecture; concluded MCP should be kept with incremental improvements ([#161](https://github.com/toba/xc-mcp/issues/161))
- Investigate XcodeBuildMCP coverage tools; no new tools needed; our `get_coverage_report` and `get_file_coverage` already cover the use cases ([#168](https://github.com/toba/xc-mcp/issues/168))
- Investigate XcodeBuildMCP xcresult/stderr output fixes; no action needed; our combined-stream approach avoids the issues by design
- Review XcodeBuildMCP v2.1.0 changes; no actionable items for xc-mcp ([#164](https://github.com/toba/xc-mcp/issues/164))
- Review Sentry XcodeBuildMCP session defaults hardening; our Swift actor approach already covers the key patterns ([#94](https://github.com/toba/xc-mcp/issues/94))
- Review tuist/xcodeproj 9.10.0–9.10.1 changes ([#162](https://github.com/toba/xc-mcp/issues/162))
- Port crash-to-test association from xcsift; `BuildOutputParser` now tracks which test was running when a crash occurs and reports it in failed test diagnostics ([#153](https://github.com/toba/xc-mcp/issues/153))
- Bump XcodeProj dependency to 9.10.1 ([#152](https://github.com/toba/xc-mcp/issues/152))

## Week of Feb 22 – Feb 28, 2026

### ✨ Features

- Migrate from Foundation `Process` to `swift-subprocess`; safer process I/O; no more pipe deadlocks by design ([#101](https://github.com/toba/xc-mcp/issues/101))
- Add `validate_project` tool; catches stale embeds, missing links, and orphaned build phases before they bite you ([#135](https://github.com/toba/xc-mcp/issues/135))
- Add project configuration generation tools; create and modify test plans and schemes programmatically ([#102](https://github.com/toba/xc-mcp/issues/102))
- Add crash report search/inspect tool; dig through `~/Library/Logs/DiagnosticReports` without opening Console.app ([#127](https://github.com/toba/xc-mcp/issues/127))
- Add `check_build` tool for single-target compilation; type-check one target without rebuilding the world ([#126](https://github.com/toba/xc-mcp/issues/126))
- Debug tools now check process state before sending commands; no more mysterious hangs on crashed processes ([#133](https://github.com/toba/xc-mcp/issues/133))
- `build_debug_macos` detects early process crashes (`dyld`, `SIGABRT`) instead of silently hanging ([#132](https://github.com/toba/xc-mcp/issues/132))
- `test_macos` surfaces crash diagnostics when the test host fails to bootstrap ([#100](https://github.com/toba/xc-mcp/issues/100))
- Add test plan management tools to `xc-project`; create, query, and modify `.xctestplan` files ([#122](https://github.com/toba/xc-mcp/issues/122))
- Improve UI test and test plan ergonomics; less boilerplate, more doing ([#121](https://github.com/toba/xc-mcp/issues/121))
- Validate `only_testing` identifiers before running `xcodebuild`; catch typos before a 2-minute build ([#118](https://github.com/toba/xc-mcp/issues/118))
- Suppress non-project warnings in build output; see your warnings, not Apple's ([#98](https://github.com/toba/xc-mcp/issues/98))
- Add in-place target renaming with cross-reference updates ([#117](https://github.com/toba/xc-mcp/issues/117))
- `xc-swift` auto-detects `package_path` from working directory; one less thing to specify ([#99](https://github.com/toba/xc-mcp/issues/99))
- Add `--build-tests` flag to `swift_package_build` ([#113](https://github.com/toba/xc-mcp/issues/113))
- Add environment variable and skip filter support to `swift_package_test` ([#112](https://github.com/toba/xc-mcp/issues/112))
- Add `swift_format` and `swift_lint` tools to `xc-swift` server ([#95](https://github.com/toba/xc-mcp/issues/95))
- Register `test_sim` in the Build server so you don't need a separate simulator server ([#97](https://github.com/toba/xc-mcp/issues/97))
- Support `XCLocalSwiftPackageReference` deletion via XcodeProj 9.9.0 ([#108](https://github.com/toba/xc-mcp/issues/108))
- `launch_mac_app` / `build_run_macos` return PID and detect early exit ([#139](https://github.com/toba/xc-mcp/issues/139))
- `debug_attach_sim` supports macOS apps by `bundle_id` without requiring a simulator ([#140](https://github.com/toba/xc-mcp/issues/140))
- Add `get_test_attachments` tool; extract screenshots and data files from `.xcresult` bundles with test ID and failure filtering ([#144](https://github.com/toba/xc-mcp/issues/144))
- Add persistent custom env vars to session defaults; `set_session_defaults(env: {...})` deep-merges and applies to all build/test/run commands ([#148](https://github.com/toba/xc-mcp/issues/148))
- Suggest correct scheme when test target isn't in the specified scheme; no more guessing which scheme has your tests ([#145](https://github.com/toba/xc-mcp/issues/145))
- `start_mac_log_cap` fixes `bundle_id` predicate reliability; adds `level` parameter and stream health checks ([#147](https://github.com/toba/xc-mcp/issues/147))

### 🐞 Fixes

- Fix pipe deadlock; drain stdout/stderr before `waitUntilExit`; was causing intermittent server hangs ([#119](https://github.com/toba/xc-mcp/issues/119))
- Fix `xcodebuild` process not killed on MCP cancellation; orphaned builds no more ([#104](https://github.com/toba/xc-mcp/issues/104))
- Fix `build_debug_macos` falsely reporting crash on successful launch ([#137](https://github.com/toba/xc-mcp/issues/137))
- Fix process interrupt via `debug_lldb_command` racing with async stop notification ([#136](https://github.com/toba/xc-mcp/issues/136))
- Reload shared session file on access so focused servers stay in sync ([#138](https://github.com/toba/xc-mcp/issues/138))
- Fix `debug_stack` thread backtrace syntax ([#131](https://github.com/toba/xc-mcp/issues/131))
- Fix `stop_mac_app` hanging when process is crashed or under LLDB ([#130](https://github.com/toba/xc-mcp/issues/130))
- `test_macos` no longer reports success when `only_testing` filter matches zero tests ([#129](https://github.com/toba/xc-mcp/issues/129))
- Use parsed build output status instead of exit code alone; catches builds that "succeed" with errors ([#115](https://github.com/toba/xc-mcp/issues/115))
- Fix `list_files` missing files from synchronized folder targets ([#106](https://github.com/toba/xc-mcp/issues/106))
- Fix `list_test_plan_targets` failing on relative project paths ([#120](https://github.com/toba/xc-mcp/issues/120))
- Fix `search_crash_reports` requiring `process_name` or `bundle_id` when neither should be mandatory ([#123](https://github.com/toba/xc-mcp/issues/123))
- Add timeout support to `SwiftRunner`; prevents runaway swift commands ([#125](https://github.com/toba/xc-mcp/issues/125))
- Fix `build_run_macos` / `launch_mac_app` crashing on non-embedded frameworks; symlink from `BUILT_PRODUCTS_DIR` instead of relying on `DYLD_FRAMEWORK_PATH` ([#141](https://github.com/toba/xc-mcp/issues/141))
- Fix `build_debug_macos` timeout with `stop_at_entry`; resolve actual executable name instead of `.app` folder name ([#142](https://github.com/toba/xc-mcp/issues/142))
- Fix `debug_detach` rejecting valid PID parameter; `getInt` now handles JSON numbers decoded as doubles ([#143](https://github.com/toba/xc-mcp/issues/143))
- Fix `get_test_attachments` parsing manifest with wrong keys; returns `Unnamed`/`unknown` for all attachments ([#146](https://github.com/toba/xc-mcp/issues/146))
- Fix `create_xcodeproj` creating orphan default target; `add_swift_package` not linking to Frameworks build phase; `add_framework` using wrong `sourceTree` for developer frameworks; `add_target` setting `TARGETED_DEVICE_FAMILY` for macOS; missing `ALWAYS_SEARCH_USER_PATHS = NO`

### 🗜️ Tweaks

- Redesign integration tests for speed; split slow tests behind `RUN_SLOW_TESTS` flag ([#96](https://github.com/toba/xc-mcp/issues/96))
- Bump XcodeProj to 9.10.1; picks up Xcode 26 `dstSubfolder` support and `CommentedString` perf fix ([#149](https://github.com/toba/xc-mcp/issues/149))

## Week of Feb 15 – Feb 21, 2026

### ✨ Features

- Add `build_debug_macos`; launch macOS apps under LLDB, the way Xcode's Run button does ([#4](https://github.com/toba/xc-mcp/issues/4))
- Add 8 new LLDB debug tools; watchpoints, memory reads, symbol lookup, view hierarchy dumps, and more ([#1](https://github.com/toba/xc-mcp/issues/1))
- Add `interact_` tools for macOS app UI interaction via Accessibility API; click, type, inspect UI trees ([#60](https://github.com/toba/xc-mcp/issues/60))
- Add `screenshot_mac_window` tool; capture any window via ScreenCaptureKit without needing a simulator ([#58](https://github.com/toba/xc-mcp/issues/58))
- SwiftUI preview capture tool; render `#Preview` macros to images on a simulator ([#59](https://github.com/toba/xc-mcp/issues/59))
- Add macOS log capture tools; stream and filter unified logs per-app ([#8](https://github.com/toba/xc-mcp/issues/8))
- Share session defaults across MCP servers; set once, use everywhere ([#32](https://github.com/toba/xc-mcp/issues/32))
- Add `rename_target` tool with cross-reference updates across schemes, dependencies, and build phases ([#111](https://github.com/toba/xc-mcp/issues/111))
- Add `remove_group`, `remove_target_from_synchronized_folder`, and exception set tools ([#103](https://github.com/toba/xc-mcp/issues/103), [#128](https://github.com/toba/xc-mcp/issues/128), [#107](https://github.com/toba/xc-mcp/issues/107))
- Add tool to share existing synchronized folder with another target ([#72](https://github.com/toba/xc-mcp/issues/72))
- Improve `test_macos` ergonomics; timeout parameter, better error surfacing from xcresults ([#109](https://github.com/toba/xc-mcp/issues/109))
- Doctor, gesture presets, Xcode state sync, next-step hints, and workflow management; a batch of quality-of-life tools ([#81](https://github.com/toba/xc-mcp/issues/81))

### 🐞 Fixes

- Fix LLDB sessions hanging; switch from pipes to PTY for stdin, matching how real terminals work ([#33](https://github.com/toba/xc-mcp/issues/33))
- Fix debug tools hanging due to ephemeral LLDB sessions that vanish mid-command ([#11](https://github.com/toba/xc-mcp/issues/11))
- Fix `build_debug_macos` `SIGABRT` crash; launch via Launch Services instead of direct LLDB process launch ([#9](https://github.com/toba/xc-mcp/issues/9))
- Fix `build_debug_macos` producing no useful error on failure ([#38](https://github.com/toba/xc-mcp/issues/38))
- Fix `debug_attach_sim` and `debug_breakpoint_add` hanging on macOS native apps ([#27](https://github.com/toba/xc-mcp/issues/27))
- Fix `preview_capture` compiler crash from `#Preview` in additional source files ([#63](https://github.com/toba/xc-mcp/issues/63))
- Fix `preview_capture` build config to avoid `ASTMangler` crash and launch failure ([#62](https://github.com/toba/xc-mcp/issues/62))
- Fix `preview_capture` for local Swift packages missing deployment target ([#71](https://github.com/toba/xc-mcp/issues/71))
- Fix `add_target` setting wrong bundle identifier key ([#79](https://github.com/toba/xc-mcp/issues/79))
- Fix `add_target` missing `productReference` and Products group entry ([#80](https://github.com/toba/xc-mcp/issues/80))
- Fix `add_framework` creating duplicate file references instead of reusing `BUILT_PRODUCTS_DIR` ([#73](https://github.com/toba/xc-mcp/issues/73), [#74](https://github.com/toba/xc-mcp/issues/74))
- Fix `list_files` to include synchronized folder contributions ([#105](https://github.com/toba/xc-mcp/issues/105))
- Fix `rename_target` gaps found during real-world module rename ([#110](https://github.com/toba/xc-mcp/issues/110))
- Fix `test_macos` error output truncation ([#78](https://github.com/toba/xc-mcp/issues/78))
- Surface warning when `testmanagerd` crashes during test run ([#77](https://github.com/toba/xc-mcp/issues/77))
- Fix `swift-frontend` SILGen crash when building IceCubesApp fixture ([#65](https://github.com/toba/xc-mcp/issues/65), [#64](https://github.com/toba/xc-mcp/issues/64))
- Fix IceCubesApp full build crash with Xcode 26 ([#70](https://github.com/toba/xc-mcp/issues/70))
- Fix Alamofire fixture build with Xcode 26 ([#69](https://github.com/toba/xc-mcp/issues/69))
- Fix `buildRunScreenshot` installing wrong platform build ([#68](https://github.com/toba/xc-mcp/issues/68))
- Fix integration test failures for `preview_capture` and IceCubesApp ([#67](https://github.com/toba/xc-mcp/issues/67), [#66](https://github.com/toba/xc-mcp/issues/66), [#91](https://github.com/toba/xc-mcp/issues/91))
- Fix reading test stdout from XCUI tests ([#76](https://github.com/toba/xc-mcp/issues/76))

### 🗜️ Tweaks

- Extract `ProcessRunner`, `ProcessKiller`, `LogCaptureBuilder`, and `BuildSettingExtractor` utilities; less duplication, cleaner tool code ([#88](https://github.com/toba/xc-mcp/issues/88), [#84](https://github.com/toba/xc-mcp/issues/84), [#82](https://github.com/toba/xc-mcp/issues/82))
- Migrate manual argument extraction to `ArgumentExtraction` helpers ([#89](https://github.com/toba/xc-mcp/issues/89))
- Replace `DispatchQueue` usage with structured concurrency ([#83](https://github.com/toba/xc-mcp/issues/83))
- Replace `Date()` timing with `ContinuousClock` ([#86](https://github.com/toba/xc-mcp/issues/86))
- Add typed throws to `XCStringsParser` mutation methods ([#90](https://github.com/toba/xc-mcp/issues/90))
- Deduplicate batch `parseEntries` in XCStrings tools ([#85](https://github.com/toba/xc-mcp/issues/85))
- Add `reserveCapacity` to batch array loops ([#87](https://github.com/toba/xc-mcp/issues/87))
- Extract shared `findSyncGroup` and clean up sync folder tools ([#116](https://github.com/toba/xc-mcp/issues/116))
- Expose 6 implemented-but-unregistered project tools ([#124](https://github.com/toba/xc-mcp/issues/124))
- Fix `preview_capture` end-to-end rendering ([#61](https://github.com/toba/xc-mcp/issues/61))
- Fix `PreviewCaptureTool` swiftlint warnings ([#92](https://github.com/toba/xc-mcp/issues/92))

## Week of Feb 1 – Feb 7, 2026

### 🗜️ Tweaks

- Review xcsift coverage scanner optimization ([#2](https://github.com/toba/xc-mcp/issues/2))
- Review xcsift Swift Testing PR ([#14](https://github.com/toba/xc-mcp/issues/14))
- Review xcsift issue-52 fix ([#34](https://github.com/toba/xc-mcp/issues/34))
- Review xcstrings-crud `BatchWriteResult` fix ([#39](https://github.com/toba/xc-mcp/issues/39))

## Week of Jan 25 – Jan 31, 2026

### ✨ Features

- Integrate xcsift build output parsing; structured errors, warnings, and notes instead of raw `xcodebuild` noise ([#17](https://github.com/toba/xc-mcp/issues/17))
- Add granular test selection to test tools; run specific test classes or methods ([#30](https://github.com/toba/xc-mcp/issues/30))
- Add code coverage collection to test tools ([#44](https://github.com/toba/xc-mcp/issues/44))
- Add Copy Files build phase management; embed frameworks, copy resources, all the fun stuff ([#23](https://github.com/toba/xc-mcp/issues/23))
- Add `remove_synchronized_folder` tool ([#12](https://github.com/toba/xc-mcp/issues/12))

### 🐞 Fixes

- Fix MCP tools corrupting unrelated `PBXCopyFilesBuildPhase` sections; the worst kind of silent data loss ([#29](https://github.com/toba/xc-mcp/issues/29))
- Fix `set_build_setting` dropping `dstSubfolder` fields from `PBXCopyFilesBuildPhase` ([#31](https://github.com/toba/xc-mcp/issues/31))
- Fix `add_synchronized_folder` deleting scheme files on save ([#24](https://github.com/toba/xc-mcp/issues/24))
- Fix synchronized folder path handling for nested groups ([#6](https://github.com/toba/xc-mcp/issues/6))
- Fix scheme deletion; use `writePBXProj` instead of `write` to preserve `.xcscheme` files ([#40](https://github.com/toba/xc-mcp/issues/40))

### 🗜️ Tweaks

- Eliminate ~100 duplicate files across focused servers ([#25](https://github.com/toba/xc-mcp/issues/25))
- Implement review consolidation changes ([#20](https://github.com/toba/xc-mcp/issues/20))

## Week of Jan 18 – Jan 24, 2026

### ✨ Features

- Implement Homebrew package; `brew install toba/tap/xc-mcp` and you're off ([#42](https://github.com/toba/xc-mcp/issues/42))
- Add `--no-sandbox` flag to `xc-project`, `xc-build`, and `xc-strings` servers ([#13](https://github.com/toba/xc-mcp/issues/13))
- Integrate xcstrings-crud as the `xc-strings` MCP server; full localization string catalog management ([#43](https://github.com/toba/xc-mcp/issues/43))
- Improve MCP tool timeout handling with streaming progress; no more silent hangs on long builds ([#16](https://github.com/toba/xc-mcp/issues/16))
- Error handling improvements across all tools ([#37](https://github.com/toba/xc-mcp/issues/37))

### 🗜️ Tweaks

- Split `xc-mcp` into 7 focused MCP servers; smaller token footprint, faster client setup ([#5](https://github.com/toba/xc-mcp/issues/5))
- Complete all 11 implementation phases: Foundation, Simulator, Device, macOS Build, Discovery, Log Capture, Simulator Extended, LLDB Debugging, UI Automation, Swift Package Manager, Utilities ([#52](https://github.com/toba/xc-mcp/issues/52) through [50](https://github.com/toba/xc-mcp/issues/50))
- Migrate tests to Swift Testing framework with parameterized test cases ([#10](https://github.com/toba/xc-mcp/issues/10))
- Add typed throws to select methods ([#7](https://github.com/toba/xc-mcp/issues/7))
- Refactor `NSString` path manipulation to `URL` ([#3](https://github.com/toba/xc-mcp/issues/3))
- Add DocC documentation ([#41](https://github.com/toba/xc-mcp/issues/41))
- Add XCStrings test coverage ([#36](https://github.com/toba/xc-mcp/issues/36))
- Clean up unused files and update README ([#28](https://github.com/toba/xc-mcp/issues/28))
- Create Swift code review skill ([#26](https://github.com/toba/xc-mcp/issues/26))
- Code optimization pass ([#45](https://github.com/toba/xc-mcp/issues/45))
- Fix swiftlint warnings ([#22](https://github.com/toba/xc-mcp/issues/22))
- Document unexposed capabilities ([#15](https://github.com/toba/xc-mcp/issues/15))
- Unified Xcode MCP Server milestone completed ([#19](https://github.com/toba/xc-mcp/issues/19))
