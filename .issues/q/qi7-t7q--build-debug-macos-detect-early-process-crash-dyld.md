---
# qi7-t7q
title: 'build_debug_macos: detect early process crash (dyld, SIGABRT)'
status: ready
type: feature
created_at: 2026-02-25T02:00:57Z
updated_at: 2026-02-25T02:00:57Z
---

When \`build_debug_macos\` launches an app that immediately crashes (e.g. dyld symbol resolution failure), it reports success:

```
Successfully built and launched 'Standard' under debugger
PID: 86835
```

The app icon bounces in the Dock but no window appears. The agent then wastes turns trying \`debug_view_hierarchy\` and other tools before discovering the process is stopped.

**Proposed behavior:** After launching and attaching, briefly check process state (e.g. \`process status\`). If the process is stopped with a signal (SIGABRT, SIGSEGV, etc.) within a short window after launch, report the crash inline:

```
Built 'Standard' but process crashed immediately after launch
PID: 86835 — stopped (signal SIGABRT)
Stop reason: dyld: symbol not found: _$s8MathView22ElementWidthCalculatorCN

Debugger attached. Use debug_stack, debug_lldb_command for investigation.
```

This saves the agent 3-5 wasted turns and gives it immediate actionable context.

**Implementation notes:**
- After \`launchViaOpenAndAttach\`, send \`process status\` and check for stopped state
- If stopped, optionally send \`bt\` to get the crash backtrace
- Parse dyld error messages from memory if the stop reason is in dyld frames
- Short sleep (0.5–1s) may be needed to let the process crash before checking
