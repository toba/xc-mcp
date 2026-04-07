---
# tkd-jgs
title: Add build diagnostics tools for debugging silent compilation failures
status: completed
type: feature
priority: high
tags:
    - enhancement
created_at: 2026-04-07T03:12:46Z
updated_at: 2026-04-07T04:20:14Z
sync:
    github:
        issue_number: "268"
        synced_at: "2026-04-07T04:22:12Z"
---

## Problem

When debugging a silent Swift compiler crash in the Thesis project, none of the existing xc-build diagnostic tools could identify the root cause. Hours were spent manually decompressing xcactivitylog files, writing Python scripts to check OutputFileMap entries, and diffing build settings by hand. The build failure was completely silent — no `error:` output, no crash trace in the build log, and the linker step was quietly skipped.

## Proposed Tools

### 1. `check_output_file_map` — Identify missing .o files

Compare a target's OutputFileMap.json against actual files on disk in DerivedData. Report which source files compiled successfully and which produced no .o file. This is the fastest way to find silent compiler crashes — the compiler dies mid-compilation, so some .o files simply never get written.

**Input:** target name (+ optional project_path, scheme, configuration)
**Output:** list of source files with status (present/missing) for each expected .o

### 2. `extract_crash_traces` — Find compiler crashes in build logs

Parse xcactivitylog files (gzip-compressed SLF binary format) for Swift compiler crash signatures: stack traces, signal handlers, `Segmentation fault`, `Illegal instruction`, `Assertion failed`, `UNREACHABLE executed`, `Stack dump`. Return the crash trace with the source file being compiled and the compiler arguments.

**Input:** target name or build log path (optional: filter by date/build ID)
**Output:** list of crash traces with source file, compiler invocation, and signal info

### 3. `list_build_phase_status` — Check which build phases completed

For a given target, report which build phases (compile sources, link, copy resources, run scripts, etc.) actually executed in the last build and their exit status. This would have immediately revealed that Core's `Ld` (link) step was skipped.

**Input:** target name (+ optional project_path, scheme)
**Output:** ordered list of build phases with status (completed/skipped/failed/not-started) and duration

### 4. `read_serialized_diagnostics` — Decode .dia files

Read Swift/Clang serialized diagnostics (.dia) binary files from DerivedData and return structured error/warning/note messages. These files exist even when the build log is empty or truncated, and they're the ground truth for what the compiler actually reported.

**Input:** target name OR explicit .dia file path
**Output:** list of diagnostics (severity, message, file, line, column, fix-it suggestions)

### 5. `diff_build_settings` — Compare settings between targets

Diff the resolved build settings between two targets (or between two configurations of the same target). Output only the differences. This replaces the manual workflow of running `showBuildSettings` twice and diffing the output.

**Input:** target A name, target B name (+ optional configuration, project_path)
**Output:** table of setting keys where values differ, with both values shown

### 6. `show_build_dependency_graph` — Visualize build plan

Show the build dependency graph for a scheme or target: which targets depend on which, what order they build in, and (after a build) which ones succeeded/failed/were-skipped. This answers "WHY was this target's link step skipped?" — was it a dependency failure? a cycle? an up-to-date check?

**Input:** scheme or target name (+ optional project_path)
**Output:** dependency tree with build status annotations; flag any cycles or failed prerequisites that caused downstream skips

## Priority

These tools would have reduced a multi-hour debugging session to minutes. Silent compiler crashes are rare but catastrophic — when they happen, there's currently no programmatic way to diagnose them through MCP tools.

## Implementation Notes

- Tools 1, 3, 4 need DerivedData path resolution (already exists in `get_derived_data_path`)
- Tool 2 needs xcactivitylog parsing (gzip + SLF format); consider reusing `xclogparser` or similar
- Tool 5 can build on existing `show_build_settings` by running it twice and diffing
- Tool 6 can use `xcodebuild -showBuildTimingSummary` or parse the build plan from DerivedData


## Summary of Changes

Added 6 build diagnostics tools for debugging silent compilation failures:

1. **`check_output_file_map`** — Compares OutputFileMap.json against actual .o files on disk to identify missing object files (hallmark of silent compiler crashes)
2. **`extract_crash_traces`** — Searches xcactivitylog files for compiler crash signatures (segfaults, assertions, stack dumps)
3. **`list_build_phase_status`** — Reports which build phases ran and their completion status (reveals skipped link steps)
4. **`read_serialized_diagnostics`** — Decodes .dia binary files using c-index-test (ground truth diagnostics even when build log is empty)
5. **`diff_build_settings`** — Compares resolved build settings between two targets/configurations with optional key filtering
6. **`show_build_dependency_graph`** — Shows build order and target statuses to explain why targets were skipped

Supporting changes:
- Added `DerivedDataLocator` utility in Core for shared DerivedData path resolution
- Registered all 6 tools in both `BuildMCPServer` (xc-build) and `XcodeMCPServer` (monolithic)
- Added 21 tests covering schema validation, parameter requirements, and error handling

Files added:
- `Sources/Core/DerivedDataLocator.swift`
- `Sources/Tools/MacOS/CheckOutputFileMapTool.swift`
- `Sources/Tools/MacOS/ExtractCrashTracesTool.swift`
- `Sources/Tools/MacOS/ListBuildPhaseStatusTool.swift`
- `Sources/Tools/MacOS/ReadSerializedDiagnosticsTool.swift`
- `Sources/Tools/MacOS/DiffBuildSettingsTool.swift`
- `Sources/Tools/MacOS/ShowBuildDependencyGraphTool.swift`
- `Tests/BuildDiagnosticsToolTests.swift`

Files modified:
- `Sources/Servers/Build/BuildMCPServer.swift` (registration)
- `Sources/Server/XcodeMCPServer.swift` (registration)
