---
# m87-5oa
title: 'add_target: minimize default build settings'
status: completed
type: bug
priority: high
created_at: 2026-03-07T18:55:41Z
updated_at: 2026-03-07T19:06:35Z
parent: xav-ojz
sync:
    github:
        issue_number: "173"
        synced_at: "2026-03-07T19:13:27Z"
---

\`add_target\` adds build settings that should be inherited from the project level:
- ALWAYS_SEARCH_USER_PATHS = NO
- INFOPLIST_FILE = <target>/Info.plist (file doesn't exist)
- ONLY_ACTIVE_ARCH = YES (Debug only, inherited)
- TARGETED_DEVICE_FAMILY = "1,2" (inherited)
- BUNDLE_IDENTIFIER (redundant with PRODUCT_BUNDLE_IDENTIFIER)
- SWIFT_VERSION = 5.0 (should inherit)

## Fix
Minimize settings to only what's target-specific: PRODUCT_BUNDLE_IDENTIFIER, PRODUCT_NAME, SDKROOT, and GENERATE_INFOPLIST_FILE = YES. Let everything else inherit from the project.

## Tasks
- [x] Remove inherited/redundant settings from Debug and Release configs
- [x] Add GENERATE_INFOPLIST_FILE = YES instead of INFOPLIST_FILE
- [x] Update existing tests that assert on removed settings


## Summary of Changes
Reduced build settings to PRODUCT_NAME, PRODUCT_BUNDLE_IDENTIFIER, and GENERATE_INFOPLIST_FILE. Removed BUNDLE_IDENTIFIER, INFOPLIST_FILE, SWIFT_VERSION, ALWAYS_SEARCH_USER_PATHS, ONLY_ACTIVE_ARCH, TARGETED_DEVICE_FAMILY.


## Summary of Changes
Reduced build settings to PRODUCT_NAME, PRODUCT_BUNDLE_IDENTIFIER, and GENERATE_INFOPLIST_FILE. Removed BUNDLE_IDENTIFIER, INFOPLIST_FILE, SWIFT_VERSION, ALWAYS_SEARCH_USER_PATHS, ONLY_ACTIVE_ARCH, TARGETED_DEVICE_FAMILY.
