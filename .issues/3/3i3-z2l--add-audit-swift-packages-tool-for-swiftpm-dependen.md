---
# 3i3-z2l
title: Add audit_swift_packages tool for SwiftPM dependency health
status: completed
type: task
priority: normal
created_at: 2026-07-06T17:27:19Z
updated_at: 2026-07-06T17:37:33Z
sync:
    github:
        issue_number: "406"
        synced_at: "2026-07-06T18:00:39Z"
---

Adapt (reimplement, no dependency) the checks from crleonard/swift-package-audit as a read-only MCP tool.

Cross-reference declared package requirements (XcodeProj XCRemoteSwiftPackageReference) against Package.resolved pins and flag health issues.

## Todo
- [ ] PackageResolvedParser in Core (v1 + v2/v3 formats)
- [ ] AuditSwiftPackagesTool (read-only) with offline checks:
  - missing Package.resolved
  - unresolved references (declared but not pinned)
  - stale pins (pinned but not declared)
  - branch pins / revision pins / exact-version pins (stability)
  - duplicate URL forms / identity mismatches
- [ ] Register in xc-swift + monolith servers
- [ ] Tests
- [ ] Add jig citation for crleonard/swift-package-audit

## Deferred (not v1)
- Remote outdated-tag check via git ls-remote
- GitHub license API checks + YAML policy/baseline DSL (agent is the policy engine)

## Summary of Changes

Adapted (reimplemented, no dependency added) the offline health checks from crleonard/swift-package-audit.

- `Sources/Core/PackageResolvedParser.swift` — normalizes v1 (`object.pins`) and v2/v3 (`pins`) Package.resolved formats into `ResolvedPin`; SwiftPM identity normalization; embedded-workspace/package-root location discovery.
- `Sources/Tools/Project/AuditSwiftPackagesTool.swift` — read-only `audit_swift_packages` tool. Diffs declared XCRemoteSwiftPackageReference requirements vs pins. Rules: missingPackageResolved, unresolvedReference, stalePin, branchDependency, revisionDependency, exactVersion, duplicateURLForm, urlFormMismatch. Severity-grouped text report.
- Registered in monolith (`XcodeMCPServer`) and `xc-project` (`ProjectMCPServer`), beside list_swift_packages.
- Tests: `PackageResolvedParserTests` (8) + `AuditSwiftPackagesToolTests` (5) — all pass.
- jig citation added for crleonard/swift-package-audit.

Deferred (not v1): remote outdated-tag check (git ls-remote), GitHub license API + YAML policy/baseline DSL.
