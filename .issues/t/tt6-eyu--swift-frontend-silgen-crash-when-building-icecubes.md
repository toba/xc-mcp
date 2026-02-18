---
# tt6-eyu
title: swift-frontend SILGen crash when building IceCubesApp fixture
status: ready
type: bug
priority: high
created_at: 2026-02-18T01:30:00Z
updated_at: 2026-02-18T01:30:00Z
sync:
    github:
        issue_number: "64"
        synced_at: "2026-02-18T01:30:12Z"
---

swift test crashes swift-frontend every time when compiling the IceCubesApp fixture for integration tests. Crash is in SILGen Transform::transform when lowering KeyPath with typed throws function conversions. Swift 6.2.3 compiler bug.

## Tasks
- [ ] Disable IceCubesApp integration tests or pin fixture to older commit
- [ ] Add --skip filter to CI to exclude integration tests
- [ ] File Apple Feedback with crash report
- [ ] Re-enable once Xcode 16.5/Swift 6.3 ships
