---
# 66d-i7n
title: Embed Frameworks copy phase missing CodeSignOnCopy attribute
status: completed
type: bug
priority: high
created_at: 2026-04-11T15:40:11Z
updated_at: 2026-04-11T15:53:28Z
sync:
    github:
        issue_number: "270"
        synced_at: "2026-04-11T15:55:57Z"
---

When xc-project adds a framework to an "Embed Frameworks" copy phase via `add_framework` or `add_to_copy_files_phase`, the build file entry is created **without** `CodeSignOnCopy` and `RemoveHeadersOnCopy` attributes.

## Problem

For frameworks with signed seals that include Headers/Modules (like XcodeKit.framework), Xcode strips headers during the copy but does NOT re-sign the framework. This breaks the code signature:

```
a sealed resource is missing or invalid
file missing: .../XcodeKit.framework/Versions/Current/Headers/XCSourceTextRange.h
file missing: .../XcodeKit.framework/Versions/Current/Modules/module.modulemap
(etc.)
```

The result: macOS refuses to load extensions using the framework. The extension appears greyed out in System Settings > Extensions.

## Expected Behavior

The `add_to_copy_files_phase` tool docs say it "auto-defaults for 'Embed Frameworks' phases" but the attributes are NOT being set. The generated pbxproj entry is:

```
{isa = PBXBuildFile; fileRef = ...; };
```

It should be:

```
{isa = PBXBuildFile; fileRef = ...; settings = {ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }; };
```

## Found In

Swiftiomatic Xcode Source Editor Extension — XcodeKit.framework embedded in SwiftiomaticExtension target. Extension builds but won't load because the embedded XcodeKit has a broken signature.

## Fix

When `add_to_copy_files_phase` or `add_framework` targets an "Embed Frameworks" phase, automatically add `CodeSignOnCopy` and `RemoveHeadersOnCopy` attributes to the PBXBuildFile entry. This matches Xcode's own behavior when you drag a framework into the Embed Frameworks phase in the UI.


## Summary of Changes

Two bugs fixed:

1. **`AddFrameworkTool.swift`**: Developer frameworks (XcodeKit, XCTest, etc.) were classified as `isSystemFramework`, so `embed: true` was silently ignored. Changed the embed condition from `!isSystemFramework` to `!isSystemFramework || isDeveloperFramework` so developer frameworks can be embedded with `CodeSignOnCopy` and `RemoveHeadersOnCopy` attributes.

2. **`AddToCopyFilesPhase.swift`**: Auto-default attributes only triggered on phase name containing "Embed Frameworks". Now also checks `dstSubfolderSpec == .frameworks` so phases with non-standard names (e.g. "Copy Frameworks") still get the correct attributes.

Two new tests added covering both fixes.
