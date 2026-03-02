---
# utg-bhb
title: Add remove_framework tool for Xcode projects
status: completed
type: feature
priority: normal
created_at: 2026-03-01T18:52:11Z
updated_at: 2026-03-02T18:35:56Z
sync:
    github:
        issue_number: "157"
        synced_at: "2026-03-02T18:46:50Z"
---

## Problem

When replacing a framework dependency with a Swift package, there's no dedicated tool to remove a framework reference from an Xcode project. The `remove_file` tool exists but is designed for source files, not framework references in the Frameworks build phase.

Users end up trying to manually edit `.pbxproj` files, which is error-prone and defeats the purpose of having project manipulation tools.

## Desired Behavior

A `remove_framework` tool (or extending `remove_file` to handle frameworks) that:

- [x] Removes the framework from the PBXFrameworksBuildPhase
- [x] Removes the PBXBuildFile entry
- [x] Removes the PBXFileReference
- [x] Removes from any embed/copy phases if present
- [x] Works for both system frameworks and third-party .framework bundles

## Context

This came up when trying to replace a `SwiftiomaticLib.framework` with an SPM dependency. The workflow should be: remove old framework → add swift package → done. Currently the first step has no tool support.

## Related Tools

- `remove_file` — existing tool, may be extendable
- `add_swift_package` — the add side already works
- Category: `Sources/Tools/Project/`


## Summary of Changes

Implemented in commit b6deefb as `RemoveFrameworkTool.swift`. The tool removes framework references from PBXFrameworksBuildPhase, PBXBuildFile entries, PBXFileReference, and embed/copy phases. Works for both system and third-party frameworks.
