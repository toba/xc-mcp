---
# m6w-vk9
title: IceCubesApp full build crashes swift-frontend (SILGen)
status: completed
type: bug
priority: high
created_at: 2026-02-18T02:05:12Z
updated_at: 2026-02-18T02:41:50Z
sync:
    github:
        issue_number: "70"
        synced_at: "2026-02-18T03:57:20Z"
---

Building the full IceCubesApp scheme (not the preview host) crashes swift-frontend with a SILGen trap:
```
Exception Type: EXC_BREAKPOINT (SIGTRAP)
Thread 0: Transform::transform in SILGen
```

Happens in `buildRunScreenshot_IceCubesApp_sim` integration test. The preview_capture test passes because it only builds a minimal host app, not the full IceCubesApp.

Pinned to tag 2.1.3 (99484408). May need a different commit or Xcode version workaround.

Affects: `buildRunScreenshot_IceCubesApp_sim` integration test.

## Summary of Changes

Fixed by preferring stable iOS runtimes (version < 26) over iOS 26.2 beta in `IntegrationTestHelper.swift` simulator picker. iOS 26.2 causes swift-frontend SILGen crashes with older codebases.
