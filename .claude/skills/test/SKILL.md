---
name: test
description: >-
  End-to-end testing of xc-mcp MCP tools against the Thesis macOS app from ../thesis.
  Use when: (1) user says "test", "test with thesis", "try the tools", "test harness",
  "test the tool", "/test", (2) verifying any MCP tool works end-to-end (interact_,
  debug_, screenshot, build, preview_capture), (3) running a full UI automation scenario
  (build → tree → click → screenshot), (4) launching the Thesis app for manual feature
  evaluation, (5) testing MCP tools via JSON-RPC over pipes (test-debug.sh),
  (6) debugging MCP tool failures by running the server directly.
---

# Test MCP Tools

End-to-end testing of xc-mcp MCP tools by launching the Thesis macOS app and driving its UI.

## Prerequisites

- Accessibility permission granted to the terminal app (System Settings > Privacy & Security > Accessibility)
- Screen Recording permission (for screenshots)
- Thesis project at `../thesis/Thesis.xcodeproj` (scheme: `Standard`)

## Quick Test via test-debug.sh

Build xc-mcp and launch Thesis under LLDB, then use interact tools via the running MCP server:

```bash
# Build and launch (stopped at entry)
./test-debug.sh /Users/jason/Developer/toba/thesis/Thesis.xcodeproj Standard

# Or full screenshot workflow
./test-debug.sh /Users/jason/Developer/toba/thesis/Thesis.xcodeproj Standard screenshot
```

Server stderr saved to `/tmp/xc-debug-last-stderr.log`.

## Interactive Test Workflow

For testing interact tools interactively (without test-debug.sh), use the xc-mcp MCP server tools directly:

### 1. Build and Launch

```
build_debug_macos(project_path: "/Users/jason/Developer/toba/thesis/Thesis.xcodeproj", scheme: "Standard", stop_at_entry: true)
```

Extract the PID from the response.

### 2. Continue Execution

```
debug_continue(pid: <PID>)
```

Wait ~5s for UI to render.

### 3. Get UI Tree

```
interact_ui_tree(pid: <PID>, max_depth: 4)
```

Inspect the element tree. Note element IDs for interaction.

### 4. Interact

```
interact_click(pid: <PID>, element_id: <ID>)
interact_find(pid: <PID>, role: "AXButton", title: "Settings")
interact_set_value(pid: <PID>, element_id: <ID>, value: "test@example.com")
interact_menu(pid: <PID>, menu_path: ["File", "New"])
interact_key(key: "return")
interact_focus(pid: <PID>)
interact_get_value(pid: <PID>, element_id: <ID>)
```

### 5. Verify

```
screenshot_mac_window(pid: <PID>, save_path: "/tmp/interact-test.png")
```

## What to Check

- `interact_ui_tree` returns a readable tree with element IDs
- `interact_find` finds elements by role, title, identifier
- `interact_click` successfully presses buttons (verify via screenshot or tree refresh)
- `interact_set_value` populates text fields
- `interact_menu` navigates menu bar items
- `interact_key` sends keyboard input
- `interact_focus` brings app to front
- `interact_get_value` returns full attributes for an element

## Testing preview_capture

Test the preview capture tool against Thesis source files:

```
preview_capture(file_path: "/Users/jason/Developer/toba/thesis/App/Sources/SomeView.swift", project_path: "/Users/jason/Developer/toba/thesis/Thesis.xcodeproj")
```

The tool injects a temporary target, builds it, launches the preview host, and captures a screenshot. Check `/tmp/xc-debug-last-stderr.log` for build diagnostics.

## Debugging MCP Tool Failures

Run the MCP server directly via JSON-RPC over pipes using `test-debug.sh`:

```bash
# The harness manages server lifecycle (named pipe stdin, temp files for stdout/stderr)
./test-debug.sh /Users/jason/Developer/toba/thesis/Thesis.xcodeproj Standard

# Server stderr is always saved for post-mortem
cat /tmp/xc-debug-last-stderr.log
```

For manual JSON-RPC testing, send requests to the server's stdin pipe and read responses from its stdout. The harness handles initialization and tool call framing.

## Troubleshooting

- **"Accessibility permission not granted"**: Add terminal app to System Settings > Privacy & Security > Accessibility
- **"Application not found"**: Verify app is running (`ps aux | grep Thesis`)
- **"Element not found in cache"**: Call `interact_ui_tree` first to populate cache
- **Empty tree**: Increase `max_depth`, or ensure app UI has rendered (wait after `debug_continue`)
