---
# xav-ojz
title: 'xc-project: add_target gaps and scaffold_module composite tool'
status: ready
type: feature
priority: high
tags:
    - enhancement
created_at: 2026-03-07T18:53:19Z
updated_at: 2026-03-07T18:53:19Z
sync:
    github:
        issue_number: "170"
        synced_at: "2026-03-07T19:13:25Z"
---

Gaps identified from a real-world session adding a new framework module (TableView) to an Xcode project with 40+ targets. The task required ~30 MCP tool calls plus 3 manual Python scripts to patch project.pbxproj.

## Gaps

### 1. `add_target` only creates Debug/Release configs
The project has 3 build configurations (Debug, Release, Beta). `add_target` only created Debug and Release XCBuildConfiguration entries. Required a Python script to inject Beta configs and add them to the XCConfigurationList.

**Fix:** introspect the project-level XCConfigurationList and create a matching XCBuildConfiguration for every config, not just Debug/Release.

### 2. `add_target` creates groups at project root
Created \`TableView\` and \`TableViewTests\` groups at the project root level. Had to \`remove_group\` both and \`create_group\` under the correct parent (\`Components\`).

**Fix:** add \`parent_group\` parameter to \`add_target\`. When omitted, current behavior (root). When set, nest the target's group there.

### 3. `add_target` adds extraneous build settings
Added settings that should be inherited from the project level:
- \`ALWAYS_SEARCH_USER_PATHS = NO\`
- \`INFOPLIST_FILE = <target>/Info.plist\` (file doesn't exist; should use \`GENERATE_INFOPLIST_FILE = YES\` or omit)
- \`ONLY_ACTIVE_ARCH = YES\` (Debug only, inherited)
- \`TARGETED_DEVICE_FAMILY = "1,2"\` (inherited)
- \`BUNDLE_IDENTIFIER\` (redundant with \`PRODUCT_BUNDLE_IDENTIFIER\`)
- \`SWIFT_VERSION = 5.0\` (should inherit)

Required Python cleanup of all 6 config blocks (2 targets x 3 configs).

**Fix:** minimize settings to only what's target-specific (\`PRODUCT_BUNDLE_IDENTIFIER\`, \`PRODUCT_NAME\`, \`SDKROOT\`). Let everything else inherit. Or add a \`minimal_settings\` boolean.

### 4. `add_to_copy_files_phase` doesn't support attributes
Embedding a framework via the "Embed Frameworks" copy phase didn't set \`CodeSignOnCopy\` or \`RemoveHeadersOnCopy\` on the PBXBuildFile entry. Required Python patching.

**Fix:** add \`attributes\` parameter (array of strings) to \`add_to_copy_files_phase\`. Default to \`["CodeSignOnCopy", "RemoveHeadersOnCopy"]\` when the phase is "Embed Frameworks".

### 5. `add_file` inconsistent group path resolution
\`add_file\` with \`group_name: "Components/TableView"\` failed ("Group not found"), but \`add_synchronized_folder\` with the same path succeeded. Inconsistent behavior.

**Fix:** unify group path resolution across all tools.

## Composite Tool Proposal: `scaffold_module`

- [ ] A single tool that creates a framework module with test target, fully wired
- [ ] Parameters: \`name\`, \`parent_group\`, \`template_target\` (clone settings from), \`with_tests\` (bool), \`link_to\` (targets to link framework into), \`embed_in\` (targets to embed into with CodeSignOnCopy), \`test_plan\` (path), \`source_path\`, \`test_path\`
- [ ] Creates: framework target, test target, group under parent, synchronized folders for Sources/Tests, all build configs matching project, dependencies, framework links, embed phases, test plan entry
- [ ] Replaces: \`add_target\` x2 + \`create_group\` + \`add_synchronized_folder\` x2 + \`add_file\` + \`set_build_setting\` x20 + \`add_dependency\` x2 + \`add_framework\` x2 + \`add_to_copy_files_phase\` + \`add_target_to_test_plan\` = 1 call instead of ~30
