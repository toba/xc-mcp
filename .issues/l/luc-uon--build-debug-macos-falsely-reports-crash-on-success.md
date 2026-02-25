---
# luc-uon
title: build_debug_macos falsely reports crash on successful launch
status: completed
type: bug
priority: high
created_at: 2026-02-25T03:01:28Z
updated_at: 2026-02-25T03:05:10Z
sync:
    github:
        issue_number: "137"
        synced_at: "2026-02-25T03:09:14Z"
---

## Problem

\`build_debug_macos\` reported "Built 'Standard' but process crashed immediately after launch" when the app launched and ran fine. The user saw the app on screen and interacting normally.

## Root Cause

\`checkForEarlyCrash()\` in \`LLDBRunner.swift\` (~line 446) uses a non-blocking \`poll()\` on LLDB's PTY stdout 1.5s after \`continue\`. **Any** pending LLDB output is treated as a crash — the content is never inspected for actual crash indicators.

False positives occur when:
- LLDB emits library load events or attach noise within the 1.5s window
- The app emits startup log output via LLDB's stdout
- A deferred prompt or status message appears

The call site in \`launchViaOpenAndAttach\` (~line 866) unconditionally wraps the output as "Process crashed immediately after launch" without semantic checks.

## Proposed Fix

Before declaring a crash, check the output from \`readUntilPrompt()\` for semantic crash indicators:
- \`stop reason = signal\` (SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP)
- \`EXC_BAD_ACCESS\`, \`EXC_BAD_INSTRUCTION\`
- \`Process NNN exited\`

If none match, treat the output as benign startup noise and return success.

## Files

- \`Sources/Core/LLDBRunner.swift\` — \`checkForEarlyCrash()\`, \`launchViaOpenAndAttach()\`
- \`Sources/Tools/Debug/BuildDebugMacOSTool.swift\` — crash flag check


## Summary of Changes

Added semantic crash detection to `checkForEarlyCrash()` in `LLDBSession`. Previously, any pending LLDB output after the 1.5s delay was treated as a crash. Now, `outputIndicatesCrash()` checks for specific indicators:
- `stop reason = signal` (SIGABRT, SIGSEGV, etc.)
- `EXC_BAD_ACCESS`, `EXC_BAD_INSTRUCTION`, `EXC_CRASH`
- `Process NNN exited with status/signal`

Benign output (library loads, attach noise, breakpoint stops) is ignored and the method returns `nil` (no crash). Added 11 tests covering all crash patterns and false-positive scenarios.
