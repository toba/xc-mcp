---
# 57l-rn2
title: add_target sets BUNDLE_IDENTIFIER instead of PRODUCT_BUNDLE_IDENTIFIER
status: completed
type: bug
priority: high
created_at: 2026-02-18T05:22:44Z
updated_at: 2026-02-20T17:51:36Z
sync:
    github:
        issue_number: "79"
        synced_at: "2026-02-20T17:52:06Z"
---

## Problem

`add_target` sets the build setting `BUNDLE_IDENTIFIER` but Xcode's `GENERATE_INFOPLIST_FILE` uses `PRODUCT_BUNDLE_IDENTIFIER` to populate `CFBundleIdentifier` in the generated Info.plist.

Result: apps built with `GENERATE_INFOPLIST_FILE = YES` have no `CFBundleIdentifier`, causing:
- XCUI test runner fails with "CFBundleIdentifier not found in Info.plist"
- Launch Services registration failures
- Code signing issues

## Fix

`add_target` should set `PRODUCT_BUNDLE_IDENTIFIER` (the standard Xcode build setting) instead of or in addition to `BUNDLE_IDENTIFIER`.

## Discovered

DiagnosticApp target created via `add_target` — UI tests failed because the generated Info.plist had no CFBundleIdentifier.
