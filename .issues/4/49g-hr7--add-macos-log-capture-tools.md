---
# 49g-hr7
title: Add macOS log capture tools
status: ready
type: feature
created_at: 2026-02-15T05:53:58Z
updated_at: 2026-02-15T05:53:58Z
---

Add `start_mac_log_cap` / `stop_mac_log_cap` tools to the MacOS tools directory, mirroring the existing simulator log capture pattern.

## Context

Current logging tools only support simulators (`simctl spawn ... log stream`) and devices. There's no way to tail console logs from a running macOS app, which is needed for debugging issues like CloudKit sync errors without Xcode's debugger attached.

## Tasks

- [ ] Create `StartMacLogCapTool.swift` in `Sources/Tools/MacOS/`
- [ ] Create `StopMacLogCapTool.swift` in `Sources/Tools/MacOS/`
- [ ] Register tools in `XcodeMCPServer.swift`
- [ ] Use `/usr/bin/log stream` with `--predicate` filtering (subsystem, bundle ID, process name)
- [ ] Write output to temp file (e.g. `/tmp/mac_log_<bundle_id>.log`)
- [ ] Store background process for cleanup
- [ ] Add tests
- [ ] Expose via `xc-build` or `xc-debug` server (whichever is appropriate)

## Design Notes

- Follow same pattern as `StartSimLogCapTool` but use `/usr/bin/log` directly instead of `xcrun simctl spawn`
- Support filtering by: subsystem, bundle ID, process name, custom predicate
- `--style compact` for readable output
- Consider adding a `read_mac_log` tool that returns the last N lines from the capture file
