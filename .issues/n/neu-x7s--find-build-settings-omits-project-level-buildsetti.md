---
# neu-x7s
title: find_build_settings omits project-level buildSettings (misleads audits)
status: completed
type: bug
priority: normal
created_at: 2026-07-08T14:37:46Z
updated_at: 2026-07-08T14:42:20Z
sync:
    github:
        issue_number: "410"
        synced_at: "2026-07-08T14:55:33Z"
---

`find_build_settings` (and `get_build_settings`) scan only native-target buildSettings dicts and silently ignore the PBXProject-level buildSettings. This makes a build-settings audit look complete when it isn't.

## Repro / real impact

While debugging a Release link failure in the Thesis project (`Undefined symbol _relinkableLibraryClasses`), a malformed project-level flag `OTHER_LDFLAGS = "-Wl -no_exported_symbols"` (space instead of comma) was inherited by every framework and stripped their exported symbols. `find_build_settings project_path settings=[OTHER_LDFLAGS]` reported ONLY the TestSupport target (which overrides with -ObjC), so the audit concluded the malformed flag was gone. Only `show_build_settings` (fully resolved) revealed OTHER_LDFLAGS still resolving to the bad value on ThesisApp — inherited from the invisible project level.

## Ask

- `find_build_settings` should also scan the project-level buildSettings and report matches with a synthetic target label (e.g. `[project]` or `(project)`), OR
- at minimum document the limitation in the tool description so agents don't treat target-only results as exhaustive.

The tool description does note it reads target-level values and doesn't resolve xcconfig inheritance, but project-level buildSettings are a distinct, common source of inherited flags and deserve to be in scope for an audit tool.

## Summary of Changes

- `FindBuildSettingsTool` now scans the `PBXProject`-level `buildSettings` in
  addition to every native target, in the same single pass. Project-level
  matches are reported with a synthetic `[project]` label, making inherited
  flags (e.g. a malformed `OTHER_LDFLAGS` on the whole project) visible to an
  audit. The value filter and `configuration` filter apply uniformly across
  the project scope and all target scopes via a shared `scan` helper.
- Updated the tool description to state that it scans project- and
  target-level values (project matches labelled `[project]`), and added
  `OTHER_LDFLAGS` to the example-settings list.
- Added `Tests/FindBuildSettingsToolTests.swift` (5 tests) covering project
  path / non-empty settings validation, project-level match reporting across
  Debug+Release, and project-level value/configuration filtering.
