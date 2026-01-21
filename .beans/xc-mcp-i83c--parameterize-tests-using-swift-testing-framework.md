---
# xc-mcp-i83c
title: Parameterize tests using Swift Testing framework
status: completed
type: task
created_at: 2026-01-21T06:54:56Z
updated_at: 2026-01-21T06:54:56Z
---

Refactor the test suite to use swift-testing's parameterized testing feature (@Test(arguments:)) to reduce code duplication and improve maintainability.

## Checklist

- [x] AddTargetToolTests.swift - Parameterize 10 product type tests → 1 parameterized test
- [x] AddAppExtensionToolTests.swift - Parameterize 4 extension type tests → 1 parameterized test
- [x] AddSwiftPackageToolTests.swift - Parameterize 3 requirement tests → 1 parameterized test
- [x] MoveFileToolTests.swift - Parameterize 3 missing param tests → 1 parameterized test
- [x] SetBuildSettingToolTests.swift - Parameterize 5 missing param checks → 1 parameterized test
- [x] AddBuildPhaseToolTests.swift - Parameterize missing param checks
- [x] AddDependencyToolTests.swift - Parameterize missing param checks
- [x] AddFileToolTests.swift - Parameterize missing param checks
- [x] AddFolderToolTests.swift - Parameterize missing param checks
- [x] AddFrameworkToolTests.swift - Parameterize missing param checks
- [x] RemoveFileToolTests.swift - Parameterize missing param checks
- [x] RemoveSwiftPackageToolTests.swift - Parameterize missing param checks
- [x] Verify all tests pass
