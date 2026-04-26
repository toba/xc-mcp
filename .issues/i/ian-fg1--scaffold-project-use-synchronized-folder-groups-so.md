---
# ian-fg1
title: 'scaffold_*_project: use synchronized folder groups so add_file isn''t needed for new sources'
status: in-progress
type: feature
priority: high
tags:
    - enhancement
created_at: 2026-04-25T21:03:53Z
updated_at: 2026-04-25T21:04:12Z
sync:
    github:
        issue_number: "286"
        synced_at: "2026-04-26T01:38:47Z"
---

## Context

While building a SwiftUI macOS app on top of `scaffold_macos_project`, every new Swift source file required a separate `mcp__xc-project__add_file` call to wire it into the .pbxproj before the build would pick it up. With Xcode 16+'s `PBXFileSystemSynchronizedRootGroup`, files added to a folder on disk are automatically included in the build — no project file edits required.

## Problem

The `Xcode/Lyrico.xcodeproj/project.pbxproj` produced by `scaffold_macos_project` uses traditional `PBXGroup` + `PBXFileReference` + `PBXSourcesBuildPhase` entries (`objectVersion = 60`). Adding a new `Foo.swift` to the source folder doesn't compile until `add_file` is called.

For an LLM agent driving the project, this means:
- Two-step file creation (Write + add_file MCP)
- Easy to forget the second step → surprising "file not found in target" errors
- Project file churn for every new source file

## Proposal

Default scaffolds (both `scaffold_macos_project` and `scaffold_ios_project`) to `objectVersion = 100` with `PBXFileSystemSynchronizedRootGroup` for the app's source folder (and a synchronized test folder if generated). Tracking issue #282 already covers parsing/maintaining objectVersion 100 projects — this is the scaffold-side counterpart so newly created projects benefit by default.

Add a `use_synchronized_folders` flag (default `true`) to opt back into the legacy layout if needed.

## Acceptance criteria

- [ ] `scaffold_macos_project` emits a project where the app source folder is a `PBXFileSystemSynchronizedRootGroup`
- [ ] `scaffold_ios_project` does the same
- [ ] Newly created `.swift` files in the synchronized folder build into the target without an `add_file` call
- [ ] `add_file` still works as a no-op (or warns) when the destination is already inside a synchronized folder
- [ ] Document the new behavior in the scaffold tool descriptions

## Related

- #282 "Handle Xcode 26 objectVersion 100 project format (synchronized folders)"
