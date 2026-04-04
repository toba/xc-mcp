---
# wkc-dy8
title: add_framework creates stale PBXFileReference for cross-project framework products
status: completed
type: bug
priority: high
created_at: 2026-04-03T23:54:10Z
updated_at: 2026-04-03T23:59:11Z
sync:
    github:
        issue_number: "258"
        synced_at: "2026-04-04T00:05:54Z"
---

## Bug

\`add_framework\` does not handle frameworks that come from cross-project references (\`PBXReferenceProxy\`). Instead of finding and reusing the existing \`PBXReferenceProxy\` entry, it creates a new \`PBXFileReference\` with \`sourceTree = \"<group>\"\`, which is incorrect and won't resolve at build time.

## Steps to reproduce

1. Have a project with a cross-project reference to another xcodeproj (e.g. GRDBCustom.xcodeproj) that produces GRDB.framework
2. The correct reference is a \`PBXReferenceProxy\` with \`sourceTree = BUILT_PRODUCTS_DIR\`:
   \`\`\`
   961FA21F2EDD34EE003CF903 /* GRDB.framework */ = {
       isa = PBXReferenceProxy;
       fileType = wrapper.framework;
       path = GRDB.framework;
       remoteRef = 961FA21E2EDD34EE003CF903 /* PBXContainerItemProxy */;
       sourceTree = BUILT_PRODUCTS_DIR;
   };
   \`\`\`
3. Call \`add_framework\` with \`framework_name: "GRDB.framework"\` and \`target_name: "TestSupport"\`
4. Tool reports success

## Expected

The tool finds the existing \`PBXReferenceProxy\` for GRDB.framework and creates a \`PBXBuildFile\` referencing it (fileRef = \`961FA21F2EDD34EE003CF903\`).

## Actual

The tool creates a NEW \`PBXFileReference\` with a generated ID:
\`\`\`
6A6C3992016A8C58A8642598 /* GRDB.framework */ = {
    isa = PBXFileReference;
    lastKnownFileType = wrapper.framework;
    name = GRDB.framework;
    path = GRDB.framework;
    sourceTree = "<group>";
};
\`\`\`

The \`PBXBuildFile\` then references this wrong entry:
\`\`\`
8F080F982481D4C430A973F2 /* GRDB.framework in Frameworks */ = {
    isa = PBXBuildFile;
    fileRef = 6A6C3992016A8C58A8642598 /* GRDB.framework */;
};
\`\`\`

This won't resolve at link time because the stale file reference doesn't point to the actual build product.

## Context

The v0r-tum fix correctly handles frameworks that are products of the SAME project (\`PBXFileReference\` with \`sourceTree = BUILT_PRODUCTS_DIR\`), but it doesn't search \`PBXReferenceProxy\` entries. Cross-project references use \`PBXReferenceProxy\` + \`PBXContainerItemProxy\` to point to products of embedded .xcodeproj subprojects.

### How other targets link correctly

The Core target links GRDB.framework correctly:
\`\`\`
961FA2222EDD3623003CF903 /* GRDB.framework in Frameworks */ = {
    isa = PBXBuildFile;
    fileRef = 961FA21F2EDD34EE003CF903 /* GRDB.framework */;
    platformFilters = (ios, macos, );
};
\`\`\`

## Suggested fix

In \`AddFrameworkTool.execute()\`, after checking local project products (PBXFileReference with BUILT_PRODUCTS_DIR), also check \`PBXReferenceProxy\` entries. If a matching framework is found as a reference proxy, reuse that entry's ID as the fileRef for the new PBXBuildFile.

Search order should be:
1. Existing PBXBuildFile already in the target (duplicate check)
2. PBXFileReference in BUILT_PRODUCTS_DIR (local product — v0r-tum fix)
3. **PBXReferenceProxy** (cross-project product — this bug)
4. System framework (sdkRoot fallback)


## Summary of Changes

Fixed `add_framework` to search `PBXReferenceProxy` entries (cross-project framework products) in addition to `PBXFileReference` entries.

### Changes

- **`Sources/Tools/Project/AddFrameworkTool.swift`**:
  - `hasLocalProduct` check now also searches `pbxproj.referenceProxies` for bare-name matching
  - Duplicate detection uses `PBXFileElement` (common base) instead of downcasting to `PBXFileReference` only
  - Framework lookup chain now includes `PBXReferenceProxy` after `PBXFileReference` (search order: local file ref → reference proxy → fallback)
  - Changed `frameworkFileRef: PBXFileReference` to `frameworkFileElement: PBXFileElement` to support both types
  - Reference proxies skip Frameworks group addition (they already live under the cross-project Products group)

- **`Tests/AddFrameworkToolTests.swift`**:
  - Added `Reuses existing PBXReferenceProxy for cross-project framework` test
  - Added `Bare name finds existing PBXReferenceProxy for cross-project framework` test
