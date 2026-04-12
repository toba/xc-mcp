---
# lo7-k5l
title: add_file does not create PBXBuildFile in PBXResourcesBuildPhase for .xcassets
status: completed
type: bug
priority: high
created_at: 2026-04-12T18:50:12Z
updated_at: 2026-04-12T19:03:22Z
sync:
    github:
        issue_number: "277"
        synced_at: "2026-04-12T19:04:28Z"
---

When \`add_file\` adds an \`.xcassets\` folder to a target, it creates the \`PBXFileReference\` (now correctly with \`lastKnownFileType = folder.assetcatalog\` after the z23-eyg fix) and adds it to the group, but it does **not**:

1. Create a \`PBXBuildFile\` entry (e.g. \`/* Assets.xcassets in Resources */\`)
2. Add that build file to the target's \`PBXResourcesBuildPhase.files\` array

## Current behavior

After \`add_file\` with \`target_name: SwiftiomaticApp\`:

\`\`\`
/* PBXBuildFile section — no Assets.xcassets entry */

19F379531543E554DDA3B9C7 /* Resources */ = {
    isa = PBXResourcesBuildPhase;
    buildActionMask = 2147483647;
    runOnlyForDeploymentPostprocessing = 0;
    /* no files array at all */
};
\`\`\`

## Expected behavior

\`\`\`
/* PBXBuildFile section */
9DFB18B93A33E405CA1BE09D /* Assets.xcassets in Resources */ = {
    isa = PBXBuildFile;
    fileRef = 340FEA820F6BC1C61AD1B9CF /* Assets.xcassets */;
};

19F379531543E554DDA3B9C7 /* Resources */ = {
    isa = PBXResourcesBuildPhase;
    buildActionMask = 2147483647;
    files = (
        9DFB18B93A33E405CA1BE09D /* Assets.xcassets in Resources */,
    );
    runOnlyForDeploymentPostprocessing = 0;
};
\`\`\`

## Impact

Without the \`PBXBuildFile\`, Xcode never runs \`CompileAssetCatalog\`. No \`Assets.car\` is produced, no \`Resources/\` directory exists in the app bundle, no \`CFBundleIconName\` is injected into Info.plist, and the app shows the generic macOS placeholder icon.

## Notes

- This likely affects all resource files added via \`add_file\`, not just \`.xcassets\`
- The \`lastKnownFileType\` fix from z23-eyg is working correctly
- The \`remove_file\` tool does correctly remove the \`PBXBuildFile\` when one exists


## Summary of Changes

`files?.append(buildFile)` is a no-op when `PBXBuildPhase.files` is `nil` (real Xcode projects omit the `files` key when a phase has no files, so XcodeProj reads it as nil). Changed all three build-phase branches in `AddFileTool` to `phase.files = (phase.files ?? []) + [buildFile]`.

Added `TestProjectHelper.createTestProjectWithNilPhaseFiles` and 2 new tests that verify resources and sources phases work correctly when starting from nil files.
