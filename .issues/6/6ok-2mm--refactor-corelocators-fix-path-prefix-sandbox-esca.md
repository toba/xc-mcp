---
# 6ok-2mm
title: 'Refactor Core/Locators: fix path-prefix sandbox escape, extract shared helpers, Codable PIF decoding, typed throws, naming/lint'
status: completed
type: task
priority: normal
created_at: 2026-07-08T16:10:03Z
updated_at: 2026-07-08T16:14:31Z
sync:
    github:
        issue_number: "417"
        synced_at: "2026-07-08T16:42:51Z"
---

Swift review findings for Sources/Core/Locators/:
- HIGH: PathUtility hasPrefix boundary bug allows /base-evil to pass sandbox check (resolvePathURL + makeRelativePath)
- extract isWorkspaceBundle predicate + findAncestorEntry helper (dedup findProjectPath/findWorkspacePath)
- PIFCacheReader: [String:Any]+JSONSerialization -> Codable DTOs (eliminate as? casts)
- PIFCacheReader: typed throws(Error); drop vestigial throws on listJSON
- PIDResolver: drop redundant MainActor.run; bundleId -> bundleID (clears lint)
- hoist regex literal; fix findAncestorDirectory doc mismatch


## Summary of Changes

- **PathUtility (HIGH — sandbox escape fix)**: Replaced raw `hasPrefix` boundary checks in `resolvePathURL` and `makeRelativePath` with `isPath(_:within:)`, which requires the match to land on a path separator (`path == base || path.hasPrefix(base + "/")`). Previously `/base-evil` passed the sandbox check for base `/base`.
- **PathUtility (dedup)**: Extracted `findAncestorEntry(matching:startingFrom:)` returning `(directory, entry)`; `findAncestorDirectory` now delegates to it. `findProjectPath`/`findWorkspacePath` no longer re-list the found directory. Extracted `isWorkspaceBundle(_:)` (was duplicated inline twice). Fixed `findAncestorDirectory` doc/signature mismatch.
- **PIFCacheReader**: Replaced `[String:Any]` + `JSONSerialization` + ~15 `as?` casts with private `Decodable` DTOs decoded via a generic `decodeEach`. `load`/`resolveDerivedDataRoot`/loaders now use `throws(Error)`; dropped vestigial `throws` on `listJSON`. Hoisted the `/[0-9a-f]{64}/` regex to a file-scope `nonisolated(unsafe) let`.
- **PIDResolver**: Dropped redundant `MainActor.run(body:)` wrapper around the already-`@MainActor` `findPID(forBundleID:)`; renamed `bundleId` -> `bundleID` (clears 6 lint warnings). Updated the two `findLaunchedPID` callers.

Build succeeds; PathUtility (17) + PIFCacheReader/DerivedDataScoper/DumpPIFTool (27) tests pass. sm format/lint clean.
