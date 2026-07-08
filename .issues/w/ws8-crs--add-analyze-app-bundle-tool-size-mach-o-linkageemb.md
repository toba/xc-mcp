---
# ws8-crs
title: 'Add analyze_app_bundle tool: size + Mach-O linkage/embedding/merge inspection for built macOS apps'
status: completed
type: feature
priority: normal
created_at: 2026-07-08T19:59:52Z
updated_at: 2026-07-08T22:53:19Z
sync:
    github:
        issue_number: "423"
        synced_at: "2026-07-08T22:57:22Z"
---

## Problem

Agents diagnosing Release binary-size / mergeable-library / embedding issues (Thesis oe2-owt, 915-unq) have no sanctioned xc-mcp tool to inspect a *built* app bundle. Today it requires ad-hoc bash: du, otool -L, otool -l (LC_RPATH), nm | grep relinkableLibraryClasses, size, plus symlink hacks to dodge spaces/parens in bundle paths. find_link_flag only reads the project file, not the built binary. get_mac_app_path returns a path but reports nothing about it.

## Concrete need that surfaced this

Measuring the Thesis Release baseline required: total bundle size; main-exe size + segment breakdown; which in-project frameworks are *linked* (otool -L @rpath) vs *embedded* (Contents/Frameworks); the app LC_RPATH set; whether the binary carries mergeable-library merge metadata (_relinkableLibraryClasses); and whether the bundle is self-contained (all @rpath deps resolvable inside it). Key gotcha learned: a loose build product is NOT self-contained (only 9 of 30 frameworks embedded; the rest resolve via DYLD_FRAMEWORK_PATH at dev-run time) -- only an archive embeds everything. The tool should make that distinction obvious instead of an agent rediscovering it via dyld crash logs.

## Proposed tool: analyze_app_bundle (read-only)

Inputs:
- app_path (string, optional): path to a .app OR .xcarchive (locate the .app inside). If omitted, resolve from session project/scheme/configuration like get_mac_app_path.
- project_path / workspace_path / scheme / configuration: same session-default resolution as get_mac_app_path.
- check_launchable (bool, default true): cross-ref linked @rpath deps vs embedded frameworks + rpaths; report any that would not resolve standalone.
- include_frameworks (bool, default true): per-embedded-framework binary sizes.

Outputs (text; consider a structured JSON block too):
- Bundle: total size (bytes + human), resource-vs-binary split.
- Main executable: path, file size, Mach-O segment sizes (__TEXT, __DATA). EXCLUDE __PAGEZERO (its 4GB vmsize makes size print a confusing ~4.3GB total).
- Embedded frameworks: name + binary size + count (Contents/Frameworks incl. nested).
- Linked in-project frameworks: from otool -L, filtered to @rpath/@loader_path; count.
- LC_RPATH entries.
- Embedding completeness: linked-but-not-embedded list (the launchability gap); include package-product frameworks (e.g. ZIPFoundation_...PackageProduct).
- Merge metadata: presence/count of _relinkableLibraryClasses per Mach-O (mergeable-library marker).
- Optional per-arch via lipo if fat.

## Implementation notes

- Sources/Tools/MacOS/AnalyzeAppBundleTool.swift; register in Servers/Build/BuildMCPServer.swift, Server/XcodeMCPServer.swift, Core/MCP/ServerToolDirectory.swift (mirror GetMacAppPathTool).
- Shell to otool/size/nm/lipo/du via Process with ARGUMENT ARRAYS (never a shell string) so spaces/parens in bundle paths need no agent-side symlink hack. Sanctioned inside a tool, same as existing build-CLI/simctl shell-outs.
- Prefer parsing otool -l / size -m load commands over the size summary to avoid the __PAGEZERO artifact.
- annotations: .readOnly. Reuse BuildSettingExtractor.extractAppPath for session resolution.

## Related

- d6d-an4 (raw linker diagnostics for *failed* links) is complementary -- this tool targets *successful* build artifacts; could share a Mach-O/otool helper.
- Consumer: Thesis oe2-owt / 915-unq (mergeable-libraries baseline + measurement).

## Summary of Changes

Added `analyze_app_bundle` (read-only) — inspects a *built* macOS `.app` (or the `.app` inside a `.xcarchive`) and reports size, Mach-O linkage, embedding, and merge metadata.

**New files**
- `Sources/Tools/MacOS/AnalyzeAppBundleTool.swift` — the tool. Resolves `app_path` (or falls back to session project/scheme/configuration like `get_mac_app_path`, defaulting configuration to Release). Reports: total bundle size + binary/resource split; main-executable segment breakdown (excludes `__PAGEZERO`); architectures; `_relinkableLibraryClasses` merge-marker count; `LC_RPATH` entries; linked in-project (`@rpath`) frameworks; per-embedded-framework sizes; and an rpath-aware launchability verdict.
- `Sources/Core/BuildOutput/MachOInspector.swift` — pure, I/O-free parsers for `size -m` / `otool -L` / `otool -l` / `nm` / `lipo` output plus dyld-style `@rpath` resolution (injectable `fileExists`). Shared-Core factoring so the string logic is unit-testable and reusable by d6d-an4.
- `Tests/MachOInspectorTests.swift` — 12 swift-testing cases covering each parser and the resolution/launchability classification.

**Registration** (mirrored `get_mac_app_path`): `BuildToolName` enum + instantiation/list/dispatch in `Servers/Build/BuildMCPServer.swift`; `ToolName` enum + workflow category + instantiation/list/dispatch in `Server/XcodeMCPServer.swift`; `analyze_app_bundle` added to `Core/MCP/ServerToolDirectory.swift`.

**Key gotcha handled**: cctools `otool`/`size` re-tokenize their file argument on whitespace *internally*, so a bundle path with a space (e.g. `ThesisApp (debug).app`) fails to open even when passed as a single argv element — the exact reason agents resorted to symlink hacks. The tool creates one spaceless temp symlink to the main executable and runs all Mach-O tools against it (auto-cleaned).

**Launchability**: resolves each linked `@rpath` dep against the binary's actual `LC_RPATH` set (dyld-style) and checks whether it lands on a file *inside the bundle*. A dep that only resolves via an absolute DerivedData `PackageFrameworks` rpath is flagged as the standalone-launch gap, making the "loose build product is not self-contained; only an archive embeds everything" distinction explicit.

Verified end-to-end against the Thesis Debug build (correct sizes, segments, rpaths, and a ✅ self-contained verdict via the debug.dylib resolving through the `@executable_path` rpath) and error paths (invalid `app_path` → clean `-32602`). `swift build` clean; 12/12 tests pass; `sm`-formatted.

## Enhancement: recursive/transitive @rpath resolution (not just the app binary)

The launchability check currently cross-references only the MAIN app executable's @rpath deps against the bundle. That misses transitive framework-to-framework deps: e.g. ThesisApp embeds all 30 in-project frameworks and the app-binary check reports "✅ self-contained", but the app still dyld-crashes standalone because EPUB.framework links @rpath/ZIPFoundation_<hash>_PackageProduct.framework, which is not embedded. Package-product frameworks (ZIPFoundation, possibly OrderedCollections/HTTPTypes) that are linked only by intermediate frameworks are invisible to an app-binary-only scan.

Ask: walk the FULL dependency closure — for every Mach-O in the bundle (app binary + each embedded framework, recursively), collect its @rpath/@loader_path deps and report any that don't resolve to a file inside the bundle. Emit the complete missing set in one pass (with which embedded framework references each), so an agent can fix embedding in a single step instead of iterating launch-by-launch. This is exactly the case that made "self-contained: ✅" a false positive on the ThesisApp Release bundle (oe2-owt).

## Enhancement implemented: full-closure @rpath resolution

Extended `analyze_app_bundle`'s launchability check from an app-binary-only scan to the **full dependency closure** — the main executable plus every embedded framework/dylib — so transitive framework→framework gaps are caught in one pass.

**Core (`MachOInspector`, pure/testable)**
- `resolves(dep:rpaths:loaderDir:executableDir:appPath:fileExists:)` — generalizes dyld resolution to any image, distinguishing `@loader_path` (the loading image's dir) from `@executable_path` (the main-exe dir); the two differ for an embedded framework. `resolvesInsideBundle` now delegates to it (`loaderDir == executableDir`), keeping existing behavior/tests intact.
- `MachOImage` / `UnresolvedDep` value types + `unresolvedClosure(...)` — resolves each image against its own rpaths unioned with the main executable's (dyld accumulates LC_RPATH along the load chain), returns unresolved deps in first-seen order, each annotated with the sorted set of referencing images.

**Tool (`AnalyzeAppBundleTool`)**
- Gathers a `MachOImage` for the main exe (reusing already-parsed linkage/rpaths) + each embedded framework (`otool -L`/`-l` run concurrently via a TaskGroup), then reports the whole-closure verdict with per-dep attribution and a scanned-image/dep count.

**Two bugs found via end-to-end run and fixed**
1. Leaf-name spaces: the main executable filename itself (`ThesisApp (debug)`) has a space, so a whole-bundle symlink didn't help — otool still mis-tokenized it (0 rpaths, unparsable `size -m`). Reverted to per-binary spaceless symlinks (`spaceSafeBinaries`), built once from all binaries up front, covering both bundle-path and leaf-name spaces.
2. Install-name self-reference: `otool -L`'s first entry for a framework/dylib is its own LC_ID_DYLIB — was parsed as a dependency, making every framework "depend on itself". Now dropped for framework/dylib images.

**Verified end-to-end** against the Thesis Debug bundle (path + main-exe name both contain spaces): main exe now parses correctly (3 rpaths, segments, its debug.dylib); the closure flags 12 genuinely-missing deps including `ZIPFoundation_<hash>_PackageProduct.framework` referenced by `Ulysses.framework` — the exact transitive false-positive from the issue that an app-binary-only scan reported as "✅ self-contained". 3 new closure tests (16/16 pass); `swift build` clean; sm-formatted.
