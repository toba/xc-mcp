---
# f6b-ert
title: Add validate_project / project_doctor tool to xc-project
status: completed
type: feature
priority: normal
created_at: 2026-02-25T02:01:33Z
updated_at: 2026-03-02T18:46:25Z
sync:
    github:
        issue_number: "134"
        synced_at: "2026-03-02T18:46:50Z"
---

Add a \`validate_project\` (or \`project_doctor\`) tool to the xc-project server that checks for common pbxproj misconfigurations. This would partially automate the manual analysis done during a Thesis debugging session where:

1. A stale MathView.framework embed caused a dyld crash on launch
2. An embed phase had \`dstSubfolder = None\` instead of \`Frameworks\`
3. Multiple embed phases for the same target duplicated work

## Checks to implement

### Embed Phase Validation
- [ ] \`dstSubfolder = None\` on phases named "Embed Frameworks" (should be \`Frameworks\`)
- [ ] Duplicate framework embedding (same framework in multiple embed phases for one target)
- [x] Frameworks embedded in one app target but only symlink-resolved in another (inconsistent embedding)

### Framework Consistency
- [ ] Frameworks linked in the Frameworks build phase but not embedded anywhere (missing embed)
- [ ] Frameworks embedded but not linked (unnecessary embed)
- [ ] Embed phases with zero files (empty dead phases)

### Build Phase Hygiene
- [x] Copy Files phases referencing nonexistent files
- [x] Orphaned PBXBuildFile entries not referenced by any build phase
- [x] Build phases not referenced by any target

### Dependency Completeness
- [ ] Target links a framework but doesn't declare it as a dependency (missing PBXTargetDependency)
- [ ] Target declares a dependency but doesn't link the product

## Output format
Structured results with severity levels (error, warning, info) and actionable fix suggestions. Machine-readable JSON mode for CI integration.

## Context
This was discovered during a session where MathView.framework was physically embedded in ThesisApp (stale copy → dyld crash) while all other frameworks were only in TestApp's embed phase (resolved via DYLD_FRAMEWORK_PATH). The Core+CSL embed phase had \`dstSubfolder = None\`. All three issues required manual pbxproj reading to diagnose.

## Summary of Changes

Added 4 missing validation checks to `validate_project` tool:

1. **Copy-files dangling references** — per-target check for PBXBuildFile entries with nil file references in copy-files phases
2. **Orphaned PBXBuildFile entries** — project-level check for build files not referenced by any build phase
3. **Unreferenced build phases** — project-level check for build phases not attached to any target
4. **Inconsistent embedding across app targets** — project-level cross-target check for frameworks embedded in some but not all app targets

All 12 checks from the issue are now implemented with 14 tests (8 existing + 4 new + 2 original tests).
