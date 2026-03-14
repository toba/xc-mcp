---
# 8yx-7e8
title: build_device should return the built .app path
status: completed
type: feature
priority: high
created_at: 2026-03-14T00:31:25Z
updated_at: 2026-03-14T00:34:01Z
sync:
    github:
        issue_number: "209"
        synced_at: "2026-03-14T00:58:33Z"
---

## Problem

After `build_device` succeeds, the caller has no way to know where the `.app` bundle was written. To install on the device, you must manually search DerivedData:

```
find ~/Library/Developer/Xcode/DerivedData -name "MyApp.app" -path "*/Debug-iphoneos/*"
```

This is fragile and breaks the build → install → launch workflow.

## Proposal

`build_device` should return the path to the built `.app` bundle in its output, similar to how other build systems report their output artifacts. This enables a seamless `build_device` → `install_app_device` → `launch_app_device` pipeline without manual DerivedData searching.

## Context

Observed while building Gerg app for iPad Mini — had to shell out to `find` to locate the .app for `install_app_device`.


## Summary of Changes

- `build_device` now queries build settings after a successful build and returns the `.app` path in its output
- Uses `BuildSettingExtractor.extractAppPath` (same as `get_mac_app_path`) to extract `CODESIGNING_FOLDER_PATH`
- Passes the device destination to `showBuildSettings` so it resolves to the correct `Debug-iphoneos` build dir
- App path extraction is best-effort — if it fails, the success message still returns without it
