---
# a68-g9s
title: Share built artifacts across packages via shared .build
status: ready
type: feature
priority: low
created_at: 2026-04-30T16:03:16Z
updated_at: 2026-04-30T16:03:16Z
sync:
    github:
        issue_number: "297"
        synced_at: "2026-04-30T16:11:23Z"
---

SwiftPM's global cache deduplicates *checkouts* but not built artifacts, so two packages depending on swift-syntax each compile it from scratch. Investigate symlinking `.build/artifacts` / `.build/<triple>/debug/ModuleCache` across known packages, or wiring `SWIFTPM_PACKAGE_CACHE_DIR` and a custom built-products cache. Risk: ABI/version mismatches between packages on different Swift versions.

Follow-up to tc2-9jv.
