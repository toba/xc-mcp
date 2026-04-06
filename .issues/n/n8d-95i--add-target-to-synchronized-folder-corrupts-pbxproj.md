---
# n8d-95i
title: add_target_to_synchronized_folder corrupts pbxproj comments and adds spurious fields
status: completed
type: bug
priority: high
created_at: 2026-04-04T00:53:38Z
updated_at: 2026-04-04T01:25:53Z
sync:
    github:
        issue_number: "260"
        synced_at: "2026-04-06T16:59:31Z"
---

## Bug

\`add_target_to_synchronized_folder\` (and possibly other tools that write to pbxproj) causes collateral corruption:

1. **Strips human-readable comments** from XCBuildConfiguration entries: \`/* Debug configuration for PBXNativeTarget "CoreTests" */\` becomes \`/* Debug */\`
2. **Strips human-readable comments** from exception set references: \`/* Exceptions for "Sources" folder in "TestApp" target */\` becomes \`/* PBXFileSystemSynchronizedBuildFileExceptionSet */\`
3. **Adds spurious \`name = Thesis.xcodeproj\`** to PBXFileReference entries that only had \`path\`
4. **Adds spurious fields** to unrelated entries: \`buildActionMask = 2147483647\`, \`runOnlyForDeploymentPostprocessing = 0\`, \`dependencies = ()\`, \`defaultConfigurationIsVisible = 0\`

## Impact

- 287 spurious field additions in a single operation
- Comment stripping makes the pbxproj harder to read and creates massive diffs
- Same class of corruption reported in ctk-v8a (which was supposedly fixed)

## Steps to reproduce

1. Have a project with synchronized folders and multiple targets
2. Call \`add_target_to_synchronized_folder\` to add TestSupport folder to TestSupport target
3. Diff the pbxproj — hundreds of unrelated changes appear

## Tools involved

The following tools were called in sequence; the corruption likely comes from whichever tool round-trips the full pbxproj through the object model:
1. \`add_target_to_synchronized_folder(folder_path: "TestSupport", target_name: "TestSupport")\`
2. \`remove_synchronized_folder_exception(folder_path: "TestSupport", target_name: "TestSupport")\`
3. \`add_framework(target_name: "TestSupport", framework_name: "Core.framework")\`
4. \`add_framework(target_name: "TestSupport", framework_name: "GRDB.framework")\`
5. \`remove_file(file_path: "TestSupport/Traits/TestManuscriptTrait.swift")\`

## Expected

Only the targeted entries should change. Comments, formatting, and unrelated entries must be preserved.

## Context

The ctk-v8a fix introduced \`PBXProjTextEditor\` for surgical text-based edits in synchronized folder tools. But either \`add_target_to_synchronized_folder\` doesn't use it, or the text editor still round-trips through the full object model for some operations.


## Summary of Changes

Converted `add_framework` and `remove_file` tools from XcodeProj round-trip serializer (`PBXProjWriter.write`) to surgical text-based edits via `PBXProjTextEditor`. This eliminates the 287 spurious field additions, comment stripping, and `name` backfilling that occurred when these tools round-tripped the entire pbxproj through the object model.

### Changes

- **PBXProjTextEditor** (`Sources/Core/PBXProjTextEditor.swift`):
  - Added `insertBlockInSection(_:section:blockLines:)` for inserting blocks into named sections (creates section if absent)
  - Added `addBuildSettingArray(_:configUUID:key:values:)` for adding array build settings to configurations
  - Made `quotePBX` public for use by tool implementations
  - Fixed `findBlock` to match block definitions (`UUID = {`) instead of UUID references in arrays — this was a latent bug where `findBlock` could match a UUID reference in e.g. `buildPhases` before finding the actual block

- **AddFrameworkTool** (`Sources/Tools/Project/AddFrameworkTool.swift`):
  - Uses XcodeProj for read-only validation (find target, check duplicates, classify framework type, get existing UUIDs)
  - All mutations done via `PBXProjTextEditor`: inserting PBXFileReference, PBXBuildFile, PBXFrameworksBuildPhase, PBXCopyFilesBuildPhase blocks; adding references to groups, build phases, and targets
  - Removed `PBXProjWriter.write()` call

- **RemoveFileTool** (`Sources/Tools/Project/RemoveFileTool.swift`):
  - Uses XcodeProj for read-only identification of file reference, build file, build phase, and parent group UUIDs
  - All mutations done via `PBXProjTextEditor`: removing references from build phases and groups, removing PBXBuildFile and PBXFileReference blocks
  - Removed `PBXProjWriter.write()` call

All 907 tests pass.
