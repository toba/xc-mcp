---
# 7j5-2sm
title: 'doctor: detect duplicate PBXTargetDependency edges and stale-remoteInfo collisions'
status: completed
type: feature
priority: high
created_at: 2026-06-02T19:31:58Z
updated_at: 2026-06-02T19:37:36Z
sync:
    github:
        issue_number: "375"
        synced_at: "2026-06-02T20:02:36Z"
---

Surfaced while working on thesis rzc-et2. xc-build's \`doctor\` should grow checks for project structural rot that produces silent build-graph corruption:

## What to detect

1. **Duplicate PBXTargetDependency edges** — same dependent target has >1 PBXTargetDependency entries with the same \`remoteGlobalID\`. Example found in thesis: ThesisApp had two CSL edges (uuids 96C2648529182C1200F66862 and 961FAD9B2EDD38B3003CF903) both pointing at remoteGlobalID 96C2647229182C1200F66862. These collapse to one path normally but create extra graph nodes that can trigger 'Multiple targets in the build graph have the target ID …' errors when explicit modules / archive-time SDK resolution kicks in.

2. **Stale \`remoteInfo\` mismatches across edges to the same target** — multiple PBXContainerItemProxy objects with the same \`remoteGlobalID\` but different \`remoteInfo\` strings (e.g. one says \`remoteInfo = Core\`, another says \`remoteInfo = ThesisShared\`, another \`remoteInfo = ThesisKit\` — all pointing to the same Core target). \`remoteInfo\` is meant to be the cached name of the target at proxy-creation time, so divergent values indicate a target was renamed without refreshing its consumer proxies. In the modern PIF / explicit-modules build system this can cause Xcode to import the same target as distinct graph nodes that then collide with 'Multiple targets in the build graph have the target ID target-<Name>-<hash>-SDKROOT:<sdk>:SDK_VARIANT:<sdk>'.

3. **Frameworks-phase + PBXTargetDependency redundancy** — same target both appears in the consumer's PBXFrameworksBuildPhase (linking) and as a PBXTargetDependency edge (ordering). Usually fine, occasionally trips the explicit-modules planner. At least worth a 'note' severity finding.

## Suggested output

\`\`\`
[warning] Thesis.xcodeproj: duplicate PBXTargetDependency in target 'ThesisApp'
  → CSL (96C2647229182C1200F66862): 2 edges
    - 96C2648529182C1200F66862 (remoteInfo=CitationStyleLanguage)
    - 961FAD9B2EDD38B3003CF903 (remoteInfo=CitationStyleLanguage)

[warning] Thesis.xcodeproj: stale remoteInfo across edges to target 'Core' (96B8F332292FF677000C6737)
  consumers see 3 different remoteInfo values: 'Core', 'ThesisKit', 'ThesisShared'
  affected proxies (21):
    - DOM/Core: remoteInfo=ThesisKit
    - CSL/Core: remoteInfo=ThesisShared
    - … etc
\`\`\`

## Why this matters

Both classes of problem manifest as cryptic dependency-graph failures, often only at archive time. Thesis hit this on Xcode Cloud Workflow D (iOS archive) and the smoking gun was only visible after manually overriding SDKROOT to force collision into a hard error.

## Why doctor

These are project-structural checks; they should run on the project itself (no scheme/build required) so they fit \`mcp__xc-build__doctor\` (or a new \`mcp__xc-project__doctor\` if doctor is reserved for env health). Either way same semantics: parse pbxproj, group proxies by remoteGlobalID, report anomalies.

## Related

- Thesis: rzc-et2 (iOS scheme leaks macOS Core build — duplicate Core dependency edge)
- xc-mcp: 7nu-9z7 (list_dependencies / remove_dependency — already shipped; this issue is the follow-up audit tool)



## Summary of Changes

Added two new structural checks to `validate_project` (xc-project) — they're project-only audits with no scheme/build dependency, so this is the right home (the env-health `doctor` tool stays focused on the toolchain):

- **Duplicate PBXTargetDependency edges** (per-target, warning): groups `target.dependencies` by the resolved remote target identity (linked target → proxy.remoteGlobalID → uuid fallback) and flags any group with >1 edges, listing each edge's uuid + remoteInfo and pointing at `remove_dependency`.
- **Stale remoteInfo across proxies** (project-level, warning): groups every `PBXContainerItemProxy` by remoteGlobalID and flags groups where the `remoteInfo` values disagree, naming the resolved target and listing the distinct values; suggests `remove_dependency` + `add_dependency` per consumer to rebuild proxies with the current name.

Skipped #3 (frameworks-phase + dependency redundancy): firing on every well-formed framework target would be pure noise; `checkDependencyCompleteness` already covers the asymmetric (links without dep, dep without link) cases.

### Files

- `Sources/Tools/Project/ValidateProjectTool.swift`: two new private check methods plus wiring inside the per-target and project-level loops.
- `Tests/ValidateProjectToolTests.swift`: two new tests; injects a duplicate PBXTargetDependency by hand (add_dependency itself refuses re-adds) and mutates one proxy's remoteInfo to simulate the rename-without-refresh case.

All 20 ValidateProjectToolTests pass.
