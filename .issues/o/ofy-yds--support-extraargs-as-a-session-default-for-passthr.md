---
# ofy-yds
title: Support extraArgs as a session default for passthrough xcodebuild arguments
status: completed
type: feature
priority: normal
created_at: 2026-07-13T01:11:29Z
updated_at: 2026-07-13T01:26:59Z
sync:
    github:
        issue_number: "426"
        synced_at: "2026-07-13T01:27:55Z"
---

Inspired by getsentry/XcodeBuildMCP#463 (extraArgs as a session default).

## Problem
SessionDefaults (Sources/Core/Session/SessionManager.swift:8-25) stores scheme, configuration, paths, simulator/device UDID, and env — but there is no way to persist arbitrary passthrough xcodebuild arguments for a session. Callers can only pass per-invocation `build_settings` (KEY=VALUE) via ArgumentExtraction. Something like `-xcconfig`, `-skipPackagePluginValidation`, or `-parallelizeTargets` cannot be set once for the session.

## Plan
- [ ] Add `extraArgs: [String]?` to SessionDefaults + persistence
- [ ] set_session_defaults / show / clear support for extra_args
- [ ] Resolver that merges session extraArgs with per-invocation extra_args (explicit replaces/extends defaults, matching upstream semantics)
- [ ] Thread into additionalArguments in build/test/run tools
- [ ] Tests for merge ordering

Depends on nothing; can follow the simulator-platform fix.

## Summary of Changes

Added extra_args as a session default plus a per-invocation override, threaded into every xcodebuild-invoking tool.

- SessionManager (Sources/Core/Session/SessionManager.swift):
  - SessionDefaults gains extraArgs: [String]? (memberwise init defaults it to nil; optional field decodes leniently so pre-existing session files load fine).
  - Actor stores/persists/reloads/clears extraArgs; summary() prints it.
  - setDefaults(extraArgs:) uses replace semantics; an empty array clears the list.
  - New resolveExtraArgs(from:): per-invocation extra_args (presence of the key, even empty) replaces the session default; otherwise the session default is used. Mirrors upstream 'explicit replaces defaults'.
- ArgumentExtraction: new extraArgsSchemaProperty (array of strings).
- set_session_defaults: extra_args schema + parsing (empty array clears).
- Threaded resolveExtraArgs + the schema property into all 11 build/test/run tools: BuildSim, BuildRunSim, TestSim, BuildMacOS, BuildRunMacOS, Archive, TestMacOS, BuildDevice, BuildDeployDevice, TestDevice, BuildDebugMacOS. Extra args are appended last so they take precedence.
- Tests: SessionExtraArgsTests.swift (8 tests, all passing) — persistence, clear, replace vs fallback, empty-suppresses-for-one-call.
