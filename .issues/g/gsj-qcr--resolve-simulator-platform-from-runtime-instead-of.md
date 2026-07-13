---
# gsj-qcr
title: Resolve simulator platform from runtime instead of hardcoding iOS Simulator
status: completed
type: bug
priority: high
created_at: 2026-07-13T01:11:22Z
updated_at: 2026-07-13T01:16:48Z
sync:
    github:
        issue_number: "425"
        synced_at: "2026-07-13T01:27:55Z"
---

Inspired by getsentry/XcodeBuildMCP#472 (deterministic simulator platform inference).

## Problem
All simulator build/run/test tools hardcode the destination platform as `platform=iOS Simulator`:
- Sources/Tools/Simulator/BuildSimTool.swift:94
- Sources/Tools/Simulator/BuildRunSimTool.swift:90
- Sources/Tools/Simulator/TestSimTool.swift:90
- Sources/Tools/Simulator/PreviewCaptureTool.swift:262

An iOS+visionOS (or watchOS/tvOS) app targeting a non-iOS simulator builds with the wrong destination and fails. Physical-device tools already do this correctly (BuildDeviceTool resolves platform via DeviceCtlRunner.lookupDevice()).

## Data available
SimctlRunner.SimulatorDevice already carries `runtime` (e.g. com.apple.CoreSimulator.SimRuntime.xrOS-2-0) and `deviceTypeIdentifier`, but the simulator tools never inspect them for platform.

## Plan
- [ ] Add a helper that maps a resolved simulator UDID -> SimulatorDevice -> platform destination string (iOS/xrOS/watchOS/tvOS Simulator)
- [ ] Use it in BuildSimTool, BuildRunSimTool, TestSimTool, PreviewCaptureTool
- [ ] Clear error when the selected simulator's runtime is unavailable/removed (don't silently guess)
- [ ] Tests for the runtime->platform mapping

## Summary of Changes

Replaced the hardcoded platform=iOS Simulator destination in the simulator build/run/test tools with runtime-derived platform resolution.

- SimctlRunner (Sources/Core/Runners/SimctlRunner.swift):
  - Added SimulatorPlatform enum (iOS/visionOS/watchOS/tvOS) with init?(runtimeIdentifier:) that parses CoreSimulator runtime IDs (xrOS token -> visionOS Simulator destination) and a destinationName.
  - Added ResolvedSimulator struct (udid + name + platform) with a composed destination (platform=<...>,id=<udid>).
  - Added resolveForBuild(matching:) which resolves a UDID/name to a device, rejects unavailable runtimes, and infers the platform. Canonicalizes a name to its UDID so -destination id= is always valid.
  - New SimctlError.platformUndetermined case mapped to invalidParams.
- BuildSimTool / BuildRunSimTool / TestSimTool: now call resolveForBuild and use the resolved destination + UDID. Added simctlRunner dependency to BuildSimTool and TestSimTool (defaulted init param).
- Tests: SimulatorPlatformTests.swift (7 tests, all passing).

## Scope note
PreviewCaptureTool intentionally left unchanged — it builds a synthetic preview host with its own iOS/macOS fallback and _relinkableLibraryClasses handling; non-iOS preview hosts are a larger feature, out of scope.
