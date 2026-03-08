---
# knz-csl
title: 'create_scheme: support multiple build targets'
status: completed
type: feature
priority: normal
created_at: 2026-03-08T23:52:35Z
updated_at: 2026-03-08T23:55:07Z
sync:
    github:
        issue_number: "197"
        synced_at: "2026-03-08T23:55:49Z"
---

## Problem

\`create_scheme\` only accepts a single \`build_target\` string parameter. When a scheme needs multiple build targets (e.g. both ThesisApp and AdminApp for a Periphery scan scheme), the agent must manually edit the generated XML to add extra \`BuildActionEntry\` elements.

## Observed in

Thesis project session creating a dedicated Periphery scheme. After \`create_scheme\` with \`build_target: "ThesisApp"\`, had to use \`Write\` to rewrite the entire scheme XML to add AdminApp as a second build entry.

## Proposed fix

Accept \`build_targets\` (array of strings) in addition to or instead of \`build_target\` (single string). Each entry becomes a \`BuildActionEntry\` in the scheme's \`BuildAction\`. First target in the array gets used as the \`EnvironmentBuildable\` for pre-actions.

Backwards-compatible: if \`build_target\` (singular) is provided, treat as single-element array.

## Workaround

Edit the generated \`.xcscheme\` XML directly after creation.


## Summary of Changes

Updated `CreateSchemeTool` to accept `build_targets` (array of strings) in addition to `build_target` (single string):

- Added `build_targets` array parameter to the tool schema
- Each entry becomes a separate `BuildActionEntry` in the scheme's `BuildAction`
- First target in the array is used as the primary for launch action, test macro expansion, and pre-action environment buildable
- Backwards-compatible: `build_target` (singular) still works and is treated as a single-element array
- Neither parameter is individually required in the schema, but at least one must be provided at runtime
- If both are provided, `build_targets` takes precedence
