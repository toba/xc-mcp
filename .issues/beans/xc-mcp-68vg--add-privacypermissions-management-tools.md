---
# xc-mcp-68vg
title: Add privacy/permissions management tools
status: draft
type: feature
priority: normal
created_at: 2026-01-21T07:36:52Z
updated_at: 2026-02-15T20:53:11Z
sync:
    github:
        issue_number: "35"
        synced_at: "2026-02-15T22:08:23Z"
---

Add MCP tools to manage simulator privacy permissions: `privacy_grant_sim`, `privacy_revoke_sim`, `privacy_reset_sim`.

## Commands
- `xcrun simctl privacy <device> grant <permission> <bundle-id>`
- `xcrun simctl privacy <device> revoke <permission> <bundle-id>`
- `xcrun simctl privacy <device> reset <permission> [bundle-id]`

## Valid permissions
all, calendar, contacts-limited, contacts, location, location-always, photos-add, photos, media-library, microphone, motion, reminders, siri

## Implementation

### New files
- `Sources/Tools/Simulator/PrivacyGrantSimTool.swift`
- `Sources/Tools/Simulator/PrivacyRevokeSimTool.swift`
- `Sources/Tools/Simulator/PrivacyResetSimTool.swift`

### SimctlRunner changes
Add methods:
```swift
func privacyGrant(udid: String, permission: String, bundleId: String) async throws -> SimctlResult
func privacyRevoke(udid: String, permission: String, bundleId: String) async throws -> SimctlResult
func privacyReset(udid: String, permission: String, bundleId: String?) async throws -> SimctlResult
```

### Tool parameters
**grant/revoke:**
- `simulator`: string (optional)
- `permission`: string (required)
- `bundle_id`: string (required)

**reset:**
- `simulator`: string (optional)
- `permission`: string (required)
- `bundle_id`: string (optional) - if omitted, resets for all apps

## Checklist
- [ ] Add privacy methods to SimctlRunner
- [ ] Create PrivacyGrantSimTool.swift
- [ ] Create PrivacyRevokeSimTool.swift
- [ ] Create PrivacyResetSimTool.swift
- [ ] Register tools in XcodeMCPServer.swift
- [ ] Add tests
