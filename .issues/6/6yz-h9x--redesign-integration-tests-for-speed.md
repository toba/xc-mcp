---
# 6yz-h9x
title: Redesign integration tests for speed
status: completed
type: task
priority: normal
created_at: 2026-02-22T23:56:29Z
updated_at: 2026-02-22T23:57:58Z
---

Split BuildRunScreenshotIntegrationTests into BuildIntegrationTests + SlowIntegrationTests, add DiscoveryIntegrationTests with xcodebuild metadata tests, add SwiftPackageIntegrationTests, expand ProjectToolIntegrationTests

## Summary of Changes

- Split `BuildRunScreenshotIntegrationTests` into `BuildIntegrationTests` (fast builds only) and `SlowIntegrationTests` (gated behind `RUN_SLOW_TESTS=1` env var)
- Expanded `DiscoveryToolIntegrationTests` → `DiscoveryIntegrationTests` with 6 new xcodebuild metadata tests: list_schemes, show_build_settings, get_app_bundle_id, get_mac_bundle_id
- Created `SwiftPackageIntegrationTests` with swift_package_list and swift_package_build tests against the xc-mcp repo itself
- Added list_test_plan_targets and expanded find_targets tests to `ProjectToolIntegrationTests`
