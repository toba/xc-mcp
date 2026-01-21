---
# xc-mcp-dsa9
title: Add privacy/permissions management tools
status: todo
type: feature
created_at: 2026-01-21T07:37:59Z
updated_at: 2026-01-21T07:37:59Z
---

Add tools to grant, revoke, and reset privacy permissions on simulators.

## Tool Specifications

### privacy_grant_sim / privacy_revoke_sim
**Parameters:**
- simulator: string (optional)
- permission: string (required) - all, calendar, contacts, location, photos, microphone, etc.
- bundle_id: string (required)

### privacy_reset_sim
**Parameters:**
- simulator: string (optional)
- permission: string (required)
- bundle_id: string (optional) - if omitted, resets for all apps

## Implementation

### Files to create:
- Sources/Tools/Simulator/PrivacyGrantSimTool.swift
- Sources/Tools/Simulator/PrivacyRevokeSimTool.swift
- Sources/Tools/Simulator/PrivacyResetSimTool.swift

### Files to modify:
- Sources/Utilities/SimctlRunner.swift - add methods:
  - `privacyGrant(udid:permission:bundleId:)`
  - `privacyRevoke(udid:permission:bundleId:)`
  - `privacyReset(udid:permission:bundleId:)`
- Sources/Server/XcodeMCPServer.swift - register tools

## Verification
- Build: swift build
- Test by granting/revoking location permission