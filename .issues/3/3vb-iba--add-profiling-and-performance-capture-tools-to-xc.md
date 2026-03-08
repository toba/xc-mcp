---
# 3vb-iba
title: Add profiling and performance capture tools to xc-build
status: completed
type: feature
priority: high
tags:
    - xc-build
created_at: 2026-03-08T05:20:56Z
updated_at: 2026-03-08T05:29:25Z
sync:
    github:
        issue_number: "191"
        synced_at: "2026-03-08T05:42:30Z"
---

## Problem

Profiling a running macOS app from an agent session is painful. In the thesis project, we needed to diagnose a ~1s typing lag after document load. Here's what happened:

1. **Built and launched app** via `build_run_macos` — worked fine
2. **Had to `pgrep`** to find the PID — `build_run_macos` doesn't return it
3. **Ran `xctrace record`** via raw Bash — no MCP tool for this
4. **`xctrace export` failed** with `Document Missing Template Error` — trace captured but no way to extract data
5. **Fell back to `sample`** command — but session was interrupted before it could run
6. **Net result**: captured a .trace file that can only be opened in Instruments.app manually. Zero actionable data returned to the agent.

## What xc-build should provide

### 1. `build_run_macos` should return the PID
Currently returns app path only. The PID is needed for attaching profilers, samplers, and debuggers. Every time we launch an app we end up running `pgrep` immediately after.

### 2. `sample_mac_app` — Sample a running process (high priority)
Wraps the `sample` command which produces readable text call stacks. This is the single most useful profiling tool for an agent because the output is plain text.

- Input: PID or bundle_id (resolve to PID internally), duration (default 5s), sampling interval
- Output: The sample text output (heaviest stacks, sorted by frequency)
- This is lightweight, no special entitlements, and the output is immediately actionable

### 3. `start_profile` / `stop_profile` — xctrace recording lifecycle
Wraps `xctrace record` with template selection. Pairs with a new `export_profile` tool.

- Input: PID or bundle_id, template name (Time Profiler, Animation Hitches, SwiftUI, App Launch), time_limit (optional)
- Output: Path to saved .trace file, recording PID for stop

### 4. `export_profile` — Extract data from a .trace file  
Wraps `xctrace export` but handles the quirks (correct path resolution, table selection).

- Input: trace file path, table name (or "toc" to list tables)
- Output: XML/text data from the trace, or for Time Profiler specifically: heaviest stack summaries

### 5. `profile_app_launch` — One-shot app launch profiling
Combines build → launch → xctrace with "App Launch" template → stop → export summary. Single tool call to answer "why is my app slow to become responsive?"

## Priority

`sample_mac_app` is the quick win — low effort, huge value. The xctrace wrapper tools are more complex but complete the story.

## Checklist

- [x] `build_run_macos` returns PID in response (already implemented)
- [x] `sample_mac_app` tool
- [x] `start_profile` / `stop_profile` tools (already implemented as `xctrace_record` with start/stop/list actions)
- [x] `export_profile` tool (already implemented as `xctrace_export`)  
- [x] `profile_app_launch` convenience tool

## Summary of Changes

### New tools
- **`sample_mac_app`** — Wraps `/usr/bin/sample` to capture call stacks from a running macOS process. Accepts `pid` or `bundle_id` (resolved internally), with configurable duration and interval. Returns plain-text heaviest stack traces.
- **`profile_app_launch`** — One-shot app launch profiling: builds the app, launches it under `xctrace record` with a configurable Instruments template (defaults to 'App Launch'), waits for the recording to finish, and exports the trace table of contents.

### Enhancements
- **`XctraceRunner.record`** — Added `launchPath` parameter to support launching an app under xctrace (using `--launch -- <path>`) instead of only attaching to existing processes.

### Already implemented (no changes needed)
- `build_run_macos` already returns PID
- `xctrace_record` (start/stop/list) already covers the start_profile/stop_profile use case
- `xctrace_export` already covers the export_profile use case

### Registration
- Both new tools registered in `BuildMCPServer` (xc-build) and `XcodeMCPServer` (monolith)
- `ServerToolDirectory` updated with new tool names

### Tests
- 8 new tests added to `XctraceToolsTests.swift` covering schema validation and error cases for both tools
