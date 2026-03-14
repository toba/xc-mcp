---
# bpv-4ka
title: Add composite device deployment tools (stop + install + launch)
status: ready
type: feature
priority: normal
created_at: 2026-03-14T01:41:56Z
updated_at: 2026-03-14T01:41:56Z
sync:
    github:
        issue_number: "215"
        synced_at: "2026-03-14T01:42:16Z"
---

## Description

When deploying an app to a physical device during development, agents (and humans) need to run 3-4 separate steps every time:

1. Find the running process PID (`devicectl device info processes`)
2. Terminate it (`devicectl device process terminate --pid <pid>`)
3. Install the new build (`devicectl device install app`)
4. Launch the app (`devicectl device process launch`)

This is tedious and error-prone. The current `build_device` tool doesn't work (see gl6-64d), so agents fall back to `xcodebuild` + manual devicectl commands.

## Proposed Tools

### `deploy_device` (or enhance `build_run_device` if it exists)
Combine stop → install → launch into a single tool call:
- **Input**: `app_path` (path to .app bundle), `device` (UDID), optional `bundle_id`
- **Behavior**: 
  1. Look up running process by bundle_id or app name → terminate if running
  2. Install the .app bundle
  3. Launch the app
- **Output**: Confirm each step succeeded, return new PID

### `build_deploy_device`
Full pipeline: build → stop → install → launch:
- **Input**: `project_path` or `workspace_path`, `scheme`, `device` (UDID)
- **Behavior**:
  1. Build with `-destination "generic/platform=iOS"`
  2. Look up and terminate any running instance
  3. Install the built .app
  4. Launch the app
- **Output**: Build result + deployment confirmation

## Context

During a debugging session, I needed to deploy ~6 iterations of an app to an iPad mini. Each required 4 separate tool calls (or a single long bash command). A composite tool would have saved significant time and reduced errors (e.g., forgetting to terminate the old process, which means the new binary doesn't actually run).

## Related Issues

- gl6-64d: `build_device` fails to find connected device by UDID (xcodebuild destination issue)
- cfo-jj0: `stop_app_device` doesn't resolve bundle_id to PID
