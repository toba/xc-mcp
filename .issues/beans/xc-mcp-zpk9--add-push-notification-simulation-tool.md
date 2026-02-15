---
# xc-mcp-zpk9
title: Add push notification simulation tool
status: draft
type: feature
priority: normal
created_at: 2026-01-21T07:36:52Z
updated_at: 2026-02-15T20:53:20Z
sync:
    github:
        issue_number: "21"
        synced_at: "2026-02-15T22:08:22Z"
---

Add `push_sim` MCP tool to simulate push notifications on iOS simulators.

## Command
`xcrun simctl push <device> <bundle-id> <payload.json>`

## Implementation

### New file
`Sources/Tools/Simulator/PushSimTool.swift`

### SimctlRunner changes
Add method:
```swift
func push(udid: String, bundleId: String, payload: String) async throws -> SimctlResult
```

### Tool parameters
- `simulator`: string (optional, uses session default)
- `bundle_id`: string (required)
- `payload`: object (required) - APNs payload JSON

### Example payload
```json
{
  "aps": {
    "alert": { "title": "Test", "body": "Hello" },
    "badge": 1,
    "sound": "default"
  }
}
```

## Checklist
- [ ] Add `push()` method to SimctlRunner
- [ ] Create PushSimTool.swift
- [ ] Register tool in XcodeMCPServer.swift
- [ ] Add tests
