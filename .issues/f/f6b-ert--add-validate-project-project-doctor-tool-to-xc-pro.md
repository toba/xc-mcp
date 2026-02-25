---
# f6b-ert
title: Add validate_project / project_doctor tool to xc-project
status: ready
type: feature
created_at: 2026-02-25T02:01:33Z
updated_at: 2026-02-25T02:01:33Z
---

Add a \`validate_project\` (or \`project_doctor\`) tool to the xc-project server that checks for common pbxproj misconfigurations. This would partially automate the manual analysis done during a Thesis debugging session where:

1. A stale MathView.framework embed caused a dyld crash on launch
2. An embed phase had \`dstSubfolder = None\` instead of \`Frameworks\`
3. Multiple embed phases for the same target duplicated work

## Checks to implement

### Embed Phase Validation
- [ ] \`dstSubfolder = None\` on phases named "Embed Frameworks" (should be \`Frameworks\`)
- [ ] Duplicate framework embedding (same framework in multiple embed phases for one target)
- [ ] Frameworks embedded in one app target but only symlink-resolved in another (inconsistent embedding)

### Framework Consistency
- [ ] Frameworks linked in the Frameworks build phase but not embedded anywhere (missing embed)
- [ ] Frameworks embedded but not linked (unnecessary embed)
- [ ] Embed phases with zero files (empty dead phases)

### Build Phase Hygiene
- [ ] Copy Files phases referencing nonexistent files
- [ ] Orphaned PBXBuildFile entries not referenced by any build phase
- [ ] Build phases not referenced by any target

### Dependency Completeness
- [ ] Target links a framework but doesn't declare it as a dependency (missing PBXTargetDependency)
- [ ] Target declares a dependency but doesn't link the product

## Output format
Structured results with severity levels (error, warning, info) and actionable fix suggestions. Machine-readable JSON mode for CI integration.

## Context
This was discovered during a session where MathView.framework was physically embedded in ThesisApp (stale copy → dyld crash) while all other frameworks were only in TestApp's embed phase (resolved via DYLD_FRAMEWORK_PATH). The Core+CSL embed phase had \`dstSubfolder = None\`. All three issues required manual pbxproj reading to diagnose.
