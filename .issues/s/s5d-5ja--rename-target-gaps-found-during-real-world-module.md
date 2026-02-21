---
# s5d-5ja
title: rename_target gaps found during real-world module rename
status: completed
type: bug
priority: high
created_at: 2026-02-21T22:16:26Z
updated_at: 2026-02-21T22:33:53Z
---

## Context

During a real-world rename of \`DiagnosticApp\` → \`TestApp\` in the Thesis project, the agent couldn't use \`rename_target\` (it wasn't in the tool list — likely an undeployed build) and had to fall back to **15+ manual pbxproj text replacements**. Reviewing what \`rename_target\` actually does vs what the rename required reveals several gaps.

## What rename_target handles today

1. \`target.name\` and \`target.productName\`
2. Build settings: \`PRODUCT_NAME\`, \`INFOPLIST_FILE\`, \`PRODUCT_MODULE_NAME\`
3. Dependencies: \`dependency.name\` and \`targetProxy.remoteInfo\`
4. Copy files build phases: product file references
5. Product reference: \`product.path\` and \`product.name\`
6. Target group: name and path in main group hierarchy

## What was needed but missing from rename_target

### Build settings not updated
- [ ] \`PRODUCT_BUNDLE_IDENTIFIER\` — needed updating (\`com.thesisapp.diagnostic\` → \`com.thesisapp.testapp\`). Add optional \`new_bundle_identifier\` param (like \`duplicate_target\` has)
- [ ] \`BUNDLE_IDENTIFIER\` — same, this is the older variant some projects use alongside \`PRODUCT_BUNDLE_IDENTIFIER\`
- [ ] \`TEST_TARGET_NAME\` — test targets reference their host app by name; this wasn't updated. Should scan all targets' build settings for values matching the old name
- [ ] \`TEST_HOST\` — references product name in path (\`$(BUILT_PRODUCTS_DIR)/App.app/...\`); should string-replace old name with new
- [ ] \`CODE_SIGN_ENTITLEMENTS\` — path contained old folder name (\`DiagnosticApp/FixtureSeeder/...\` → \`TestApp/FixtureSeeder/...\`). Should string-replace old name with new in the value

### Other missing updates
- [ ] \`LD_RUNPATH_SEARCH_PATHS\` and \`FRAMEWORK_SEARCH_PATHS\` that embed the old target name
- [ ] Scheme files — \`BuildableName\` and \`BlueprintName\` attributes in \`.xcscheme\` files reference the target name. \`rename_target\` should scan all schemes and update references to the renamed target

## Separate tooling gaps exposed by the session

These are things the agent had to do manually that no xc-project tool covers:

### rename_scheme tool (new tool needed)
- [ ] Rename \`.xcscheme\` file on disk
- [ ] No content changes needed (BlueprintIdentifier UUIDs stay stable, BuildableName/BlueprintName should be updated by \`rename_target\` per above)

### rename_group tool (new tool needed)
- [ ] Rename a PBXGroup's \`name\` and \`path\` properties
- [ ] Distinct from target group renaming (which \`rename_target\` handles)
- [ ] Needed for renaming the top-level module folder group when the disk folder is renamed

## Reproduction

The full session is in the Thesis repo commit history on the \`develop\` branch. The agent performed these manual pbxproj edits that \`rename_target\` should have handled:
- 4 product reference edits (\`.app\`, \`.xctest\`)
- 2 target name edits
- 2 product name edits
- 4 PRODUCT_NAME edits
- 4 bundle ID edits
- 3 entitlements path edits
- 2 TEST_TARGET_NAME edits
- 1 remoteInfo edit
- 2 build config list comment edits
- 2 exception set comment edits
- 1 group path edit

Total: ~15 Edit tool calls that a robust \`rename_target\` + \`rename_scheme\` should eliminate entirely.


## Summary of Changes

### Enhanced `rename_target` tool
- Added optional `new_bundle_identifier` parameter to set `PRODUCT_BUNDLE_IDENTIFIER` and `BUNDLE_IDENTIFIER`
- Added `CODE_SIGN_ENTITLEMENTS` path string-replacement on the renamed target
- Added cross-target build settings scan: `TEST_TARGET_NAME` (exact match), `TEST_HOST` (string-replace), `LD_RUNPATH_SEARCH_PATHS` and `FRAMEWORK_SEARCH_PATHS` (string or array value replacement)
- Added scheme file updates: scans `xcshareddata/xcschemes/` and `xcuserdata/*/xcschemes/` for `BuildableName` and `BlueprintName` references

### New `rename_scheme` tool
- Renames `.xcscheme` files on disk (shared and user schemes)
- Validates scheme exists and new name doesn't conflict

### New `rename_group` tool
- Renames arbitrary PBXGroup by slash-separated path (e.g. `Sources/OldName`)
- Updates both `group.name` and `group.path`

### Server registration
- Added `rename_scheme` and `rename_group` to `XcodeMCPServer` (monolithic)
- Added `rename_target`, `rename_scheme`, and `rename_group` to `ProjectMCPServer` (focused server — `rename_target` was previously missing)

### Tests
- 5 new tests for enhanced `rename_target` (bundle ID, entitlements, cross-target settings, scheme updates, search paths)
- 5 new tests for `rename_scheme` (creation, missing params, rename, not found, name conflict)
- 5 new tests for `rename_group` (creation, missing params, rename, nested path, not found)
- All 528 tests pass (22 new)
