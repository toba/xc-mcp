---
# ybc-e83
title: log capture can't target apps with spaces/parens in process name
status: completed
type: bug
priority: normal
created_at: 2026-05-25T19:41:47Z
updated_at: 2026-05-25T19:45:05Z
sync:
    github:
        issue_number: "335"
        synced_at: "2026-05-25T19:46:49Z"
---

## Problem

`build_debug_macos` launches debug apps whose executable/process name contains spaces and parentheses, e.g. `ThesisApp (debug)` (bundle id `com.thesisapp.debug`). That process name cannot be fed back into `start_mac_log_cap`:

- `process_name` param validator rejects it: `Invalid process_name 'ThesisApp (debug)': only alphanumeric characters, dots, hyphens, and underscores are allowed.`
- `bundle_id` matching uses the last dot-component as the executable name, so `com.thesisapp.debug` → `debug`, which does not match process `ThesisApp (debug)`. Capture silently returns zero lines.

Net effect: there is no straightforward way to capture unified logs for a debug build launched via `build_debug_macos`. Falling back to a hand-written `log show --predicate 'process == "..."'` is required.

## Repro
1. `build_debug_macos` (scheme producing `ThesisApp (debug)`)
2. `start_mac_log_cap process_name='ThesisApp (debug)'` → validation error
3. `start_mac_log_cap bundle_id='com.thesisapp.debug'` → predicate `process == "debug"`, no matching logs

## Suggested fixes
- Relax `process_name` validation to allow spaces/parens (it's only interpolated into an OSLog predicate string; quote/escape it) OR accept it verbatim and rely on predicate quoting.
- Have `build_debug_macos` return the exact predicate (or a capture handle) usable by `start_mac_log_cap`, or let log capture accept a PID directly (`processID ==`).
- Fix `bundle_id`→executable derivation, or document that it assumes executable == last bundle component.

## Context
Hit while verifying Thesis (`com.thesisapp.debug`) on macOS. Worked around with `log show --predicate 'process == "ThesisApp (debug)"'` and by querying the app's own SQLite log DB.


## Summary of Changes

- Added `PredicateFilterValidator.validateStringLiteral` — a relaxed validator that permits spaces, parentheses, and other punctuation in free-form values like process names, rejecting only empty strings, newlines, and control characters.
- Added `PredicateFilterValidator.escapeStringLiteral` — escapes backslashes then double quotes so a value is safely interpolated inside a double-quoted `NSPredicate` string literal (neutralizes quote-injection without rejecting legitimate names).
- `start_mac_log_cap` and `show_mac_log` now validate `process_name` with `validateStringLiteral` and escape it on interpolation, so `process_name='ThesisApp (debug)'` works instead of failing validation.
- Updated the `process_name` schema descriptions to note spaces/parens are accepted (e.g. from a `build_debug_macos` launch).
- Updated tests: replaced the injection-rejection test for `process_name` (now escaped, not rejected) with unit tests covering `validateStringLiteral` and `escapeStringLiteral`. All 13 tests pass.

Note: the `bundle_id`→executable derivation still relies on `mdfind`/`CFBundleExecutable` and falls back to the last bundle component; passing the exact `process_name` is now the reliable path for debug builds.
