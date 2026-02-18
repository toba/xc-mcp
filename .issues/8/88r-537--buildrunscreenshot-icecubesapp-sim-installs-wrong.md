---
# 88r-537
title: buildRunScreenshot_IceCubesApp_sim installs wrong platform build
status: completed
type: bug
priority: normal
created_at: 2026-02-18T02:05:12Z
updated_at: 2026-02-18T02:41:50Z
---

Test tries to simctl install a macCatalyst build:
```
lstat of .../Debug-maccatalyst/Ice Cubes.app failed: No such file or directory
```

The build may be producing a maccatalyst build instead of iphonesimulator, or the scheme defaults to macCatalyst. Needs investigation — may be related to the SILGen crash (falls back to wrong platform).

## Summary of Changes

Fixed by adding `destination` parameter to `showBuildSettings` in XcodebuildRunner and passing it from BuildRunSimTool. Without explicit destination, xcodebuild defaulted to macCatalyst for projects with SUPPORTS_MACCATALYST=YES. Also serialized integration tests and reordered IceCubesApp tests to avoid DerivedData contamination.
