---
# xc-mcp-qem0
title: set_build_setting drops dstSubfolder fields from PBXCopyFilesBuildPhase
status: in-progress
type: bug
priority: high
created_at: 2026-01-31T02:27:46Z
updated_at: 2026-01-31T02:38:51Z
---

When using the set_build_setting tool, it rewrites the entire pbxproj file and drops `dstSubfolderSpec` fields from `PBXCopyFilesBuildPhase` sections, causing copy file build phases to target `/` instead of Resources.

## Investigation

### Unable to reproduce with XcodeProj 9.7.2

Added regression test `setBuildSettingPreservesCopyFilesPhase` in `Tests/SetBuildSettingToolTests.swift` that:
1. Creates a project with a PBXCopyFilesBuildPhase with `dstSubfolderSpec = .resources`
2. Uses `set_build_setting` to change a build setting
3. Verifies the copy files phase still has `dstSubfolderSpec = .resources`

The test **passes** — the round-trip preserves `dstSubfolderSpec` correctly.

### XcodeProj serialization analysis

Reviewed the XcodeProj library's read/write pipeline:

- **Deserialization** (`PBXCopyFilesBuildPhase.init(from:)`) uses `decodeIntIfPresent(.dstSubfolderSpec).flatMap(SubFolder.init)` — reads the integer and maps to the `SubFolder` enum
- **Serialization** (`plistKeyAndValue`) writes `dstSubfolderSpec` only if non-nil: `if let dstSubfolderSpec { dictionary["dstSubfolderSpec"] = ... }`
- **Unknown fields are lost** during round-trip — XcodeProj only preserves fields defined in its `CodingKeys` enums

### Potential causes (unconfirmed)

1. **Unrecognized SubFolder raw value**: If the pbxproj contains a `dstSubfolderSpec` integer value not in the `SubFolder` enum (values 2, 3, 4, 5, 8, 9 are unmapped), `SubFolder.init(rawValue:)` returns nil and the field is dropped on write
2. **Project-specific formatting**: Xcode-created projects may have subtle formatting differences that trip up the decoder
3. **Xcode version differences**: Newer Xcode versions might write pbxproj fields differently

### Related issues

- tuist/XcodeProj #597: Int-vs-String encoding mismatch for `dstSubfolderSpec` — fixed in 2020, included in 9.7.2
- xc-mcp-f1y3: Same symptom observed previously, also unable to reproduce

## Checklist

- [x] Investigate the serialization pipeline in XcodeProj
- [x] Add regression test for set_build_setting + dstSubfolderSpec preservation
- [ ] Reproduce with an actual Xcode-created project (need sample pbxproj that triggers the bug)

## Next steps

To investigate further, we need a pbxproj file that exhibits the issue. When the bug recurs:
1. Before running set_build_setting, save a copy of the pbxproj
2. Compare the before/after to identify exactly which fields are dropped and what their raw values were
