---
# 5m0-9rc
title: Migrate swift_lint / swift_format tools to swiftiomatic (sm)
status: completed
type: task
priority: normal
created_at: 2026-05-09T17:47:10Z
updated_at: 2026-05-09T18:26:11Z
sync:
    github:
        issue_number: "318"
        synced_at: "2026-05-09T18:27:05Z"
---

## Goal

Ensure xc-mcp and all its servers/tools only invoke or suggest `swiftiomatic` (`sm`), never `swiftlint` or `swiftformat` (Lockwood).

**Status: blocked** on upstream JSON reporters in `../swiftiomatic`:
- swiftiomatic#jfq-6g1 — Add JSON reporter for `sm lint` output
- swiftiomatic#l84-dng — Emit structured changed-files output from `sm format` (consistent envelope with lint reporter)

Once both land, this work proceeds as planned below.

## Affected files

**Source rewrites**
- `Sources/Tools/SwiftPackage/SwiftLintTool.swift` — invoke `sm lint --reporter json` (post jfq-6g1), drop SwiftLint JSON reporter logic, drop `.swiftlint.yml` discovery (sm finds `swiftiomatic.json` itself).
- `Sources/Tools/SwiftPackage/SwiftFormatTool.swift` — invoke `sm format -i -r --parallel --reporter json` (post l84-dng), drop Lockwood-vs-Apple discrimination, drop `.swiftformat` discovery.
- `Sources/Tools/SwiftPackage/SwiftDiagnosticsTool.swift` — `runSwiftLint` → `runSm`, parse new format. **Rename param `run_swiftlint` → `run_lint`** (clean break, internal-ish param).
- `Sources/Tools/MacOS/DiagnosticsTool.swift` — same rename + invocation swap.
- `Sources/Core/BinaryLocator.swift` — drop the `swiftformat` Lockwood-discrimination logic; locate `sm` at `/opt/homebrew/bin/sm` with PATH fallback.

**MCP tool surface**
- Keep tool names `swift_lint` and `swift_format` (stable client surface, internal binary swap).
- Param rename: `run_swiftlint` → `run_lint` on both diagnostics tools.

**Tests**
- Rewrite `Tests/SwiftLintToolTests.swift` for the new sm JSON envelope.
- Rewrite `Tests/SwiftFormatToolTests.swift` for the new sm format reporter.
- Leave alone: `Tests/AddBuildPhaseToolTests.swift` and `Tests/RemoveRunScriptPhaseTests.swift` — those use "SwiftLint" only as an arbitrary build-phase name in user-project fixtures, not as a binary invocation.

**Left alone**
- `// swiftlint:disable:next` comment directives in `Sources/Core/InteractRunner.swift` and `Sources/Core/CoverageParser.swift` — inert source comments, harmless.
- `Tests/Integration/IntegrationTestHelper.swift` — references the upstream SwiftFormat repo as an integration-test corpus (testing project-tool behavior on a real `.xcodeproj`), unrelated to invocation.

## sm CLI reference (current behavior)

```
sm lint [-s --strict] [-p --parallel] [--no-cache] [-r --recursive] <paths...>
  → stdout: `path:line:col: warning: [rule] message`
  → exit 0 even with findings unless `-s`

sm format [-i --in-place] [-r --recursive] [-p --parallel] <paths...>
  → stdout: formatted source (or in-place rewrite with -i)
  → no "changed files" listing
```

Once the upstream JSON reporters land, schema will be unified across both.

## Open questions resolved

1. **Param rename for diagnostics tools** → `run_swiftlint` → `run_lint` (clean break).
2. **`swift_format` changed-files reporting** → addressed by upstream issue swiftiomatic#l84-dng (emit structured output natively from `sm format`, schema consistent with the lint reporter); xc-mcp will consume it directly rather than reconstructing via mtime/hash diff.



## Summary of Changes

Migrated all swiftlint/swiftformat invocations in xc-mcp to swiftiomatic (`sm`), consuming the new JSON reporters from upstream issues swiftiomatic#jfq-6g1 and swiftiomatic#l84-dng.

**Files changed**
- `Sources/Core/BinaryLocator.swift` — dropped Lockwood-vs-Apple swiftformat discrimination; now a single PATH/Homebrew lookup that works for any binary including `sm`.
- `Sources/Tools/SwiftPackage/SwiftLintTool.swift` — invokes `sm lint --reporter json --parallel --recursive`. Field names updated: `rule_id` → `rule`, `character` → `column`, `reason` → `message`. Dropped `fix` parameter (sm doesn't expose autofix on the CLI yet) and dropped `.swiftlint.yml` discovery (sm finds its configuration itself).
- `Sources/Tools/SwiftPackage/SwiftFormatTool.swift` — invokes `sm format --in-place --recursive --parallel --reporter json`. Replaced verbose-output regex with structured `{changed, unchanged, skipped}` envelope parsing. Dropped `dry_run` parameter (sm doesn't have a dry-run mode yet) and `.swiftformat` discovery.
- `Sources/Tools/SwiftPackage/SwiftDiagnosticsTool.swift` — `runSwiftLint` → `runSm`. Param rename `include_lint` → `run_lint`.
- `Sources/Tools/MacOS/DiagnosticsTool.swift` — same rename + invocation swap.
- `Tests/SwiftLintToolTests.swift` — rewritten for sm JSON envelope.
- `Tests/SwiftFormatToolTests.swift` — rewritten for sm format reporter (changed/unchanged/skipped).

**Tool surface**
- MCP tool names `swift_lint` and `swift_format` kept stable (internal binary swap).
- Diagnostics param renamed `include_lint` → `run_lint` on both `swift_diagnostics` and `diagnostics`.

**Verification**
- `swift build` clean.
- Affected unit tests: 12/12 pass.
- Full suite: 1118/1118 pass.
- Source files re-formatted with `sm format` (dogfooding the new tooling).
