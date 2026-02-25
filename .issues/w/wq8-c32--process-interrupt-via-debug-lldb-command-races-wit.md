---
# wq8-c32
title: process interrupt via debug_lldb_command races with async stop notification
status: completed
type: bug
priority: high
created_at: 2026-02-25T03:01:28Z
updated_at: 2026-02-25T03:06:50Z
---

## Problem

Running \`process interrupt\` via \`debug_lldb_command\` appears to succeed but doesn't update process state. A subsequent \`debug_stack\` call fails with "Process is running. Interrupt it first." However, running \`bt all\` via \`debug_lldb_command\` works because it implicitly waits for the stop.

## Root Cause

\`executeCommand\` relies on \`updateProcessState(from: output)\` to detect state changes by pattern-matching LLDB output. But \`process interrupt\` sends a signal asynchronously — LLDB may emit the \`(lldb)\` prompt **before** the target actually stops. \`readUntilPrompt()\` returns early with no stop-indicating text, so \`processState\` stays \`.running\`.

By contrast, \`bt all\` is a blocking command that only returns after the process stops, so the output always contains \`stop reason =\` text.

| Command | State update | Reliable? |
|---|---|---|
| \`continue\` (debug_continue) | Explicit \`setProcessState(.running)\` | Yes |
| \`process interrupt\` (debug_lldb_command) | Output pattern match only | No — async race |
| \`bt all\` (debug_lldb_command) | Output pattern match, but blocks until stopped | Yes |

## Proposed Fix

Detect \`process interrupt\` in \`executeCommand\` and handle it specially: after sending the command, poll for the async stop notification (similar to \`checkForEarlyCrash\` pattern) and explicitly set \`processState = .stopped(...)\` once confirmed. Alternatively, add a dedicated \`interruptProcess()\` method.

## Files

- \`Sources/Core/LLDBRunner.swift\` — \`executeCommand()\`, \`updateProcessState()\`


## Summary of Changes

Added `interruptProcess(timeout:)` method to `LLDBSession` that properly handles the asynchronous nature of `process interrupt`:

1. Sends `process interrupt` via `sendCommand`
2. If the initial output already contains stop info, returns immediately
3. Otherwise, polls for the async stop notification (up to 5s timeout)
4. Explicitly sets `processState = .stopped` once confirmed

Updated `executeCommand()` in `LLDBRunner` to detect `process interrupt` commands and route them through the new handler instead of plain `sendCommand`. This ensures that `debug_stack` and other state-checking tools work immediately after an interrupt without the "Process is running" error.
