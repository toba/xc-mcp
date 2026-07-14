---
# bix-ohr
title: Adopt XcodeProj 9.14.0 SwiftPackage traits support
status: in-progress
type: feature
priority: normal
created_at: 2026-07-14T19:26:07Z
updated_at: 2026-07-14T19:26:07Z
sync:
    github:
        issue_number: "428"
        synced_at: "2026-07-14T19:55:21Z"
---

Upstream tuist/xcodeproj 9.14.0 (commit 9b7b9d5, PR #1114) adds `traits` to XCRemoteSwiftPackageReference and XCLocalSwiftPackageReference, enabling SwiftPM package-trait declarations in .xcodeproj files.

## Impact on xc-mcp
Tools that construct/read these reference types could surface or set package traits:
- AddSwiftPackageTool.swift — builds XCRemoteSwiftPackageReference / XCLocalSwiftPackageReference
- AddPackageProductTool.swift — resolves references
- RemoveSwiftPackageTool.swift
- ListSwiftPackagesTool.swift — could display traits
- AuditSwiftPackagesTool.swift

## Tasks
- [ ] Bump XcodeProj floor to 9.14.0 in Package.swift + resolve
- [ ] Surface traits in ListSwiftPackagesTool output
- [ ] Accept optional traits arg in AddSwiftPackageTool / AddPackageProductTool
- [ ] Add round-trip tests

Source: cite review 2026-07-14, tuist/xcodeproj@9b7b9d5
