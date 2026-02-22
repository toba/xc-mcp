---
# 45c-v12
title: Add check_build tool for single-target compilation
status: in-progress
type: feature
priority: normal
created_at: 2026-02-22T00:26:08Z
updated_at: 2026-02-22T00:34:59Z
---

## Problem

When Claude edits files in a non-primary target (e.g. test support files in `DOMTests`), missing imports or type errors aren't caught until a full scheme build or test run — which is slow. In Xcode, SourceKit shows these immediately as inline diagnostics. A lightweight tool that builds a single target via `xcodebuild -target` would give fast feedback (seconds vs minutes).

### Real-world example

Editing `MockTextView.swift` in `DOMTests` to use a new type from `Core` — a missing `import Core` wasn't caught until a full test run failed, wasting a complete build cycle. A `check_build -target DOMTests` would have caught it in seconds.

## Proposal

Add a `check_build` tool to the `xc-build` server that builds a single target using `-target` instead of `-scheme`.

### `Sources/Core/XcodebuildRunner.swift`

Add a `buildTarget()` method alongside the existing `build()`:

\`\`\`swift
public func buildTarget(
    projectPath: String? = nil,
    workspacePath: String? = nil,
    target: String,
    destination: String,
    configuration: String = "Debug",
    additionalArguments: [String] = [],
    timeout: TimeInterval = defaultTimeout,
    onProgress: (@Sendable (String) -> Void)? = nil
) async throws -> XcodebuildResult {
    var args: [String] = []
    if let workspacePath {
        args += ["-workspace", workspacePath]
    } else if let projectPath {
        args += ["-project", projectPath]
    }
    args += [
        "-target", target,
        "-destination", destination,
        "-configuration", configuration,
        "build",
    ]
    args += additionalArguments
    return try await run(arguments: args, timeout: timeout, onProgress: onProgress)
}
\`\`\`

### \`Sources/Tools/MacOS/CheckBuildTool.swift\` (new)

New tool struct following \`BuildMacOSTool\` pattern:
- Tool name: \`check_build\`
- Parameters: \`project_path\`, \`workspace_path\`, \`target_name\` (required), \`configuration\`, \`destination\` (optional, defaults to \`platform=macOS\`)
- Uses \`xcodebuildRunner.buildTarget()\` instead of \`.build()\`
- Returns same error format via \`ErrorExtractor.parseBuildOutput()\`
- No scheme resolution — uses \`-target\` directly
- Does NOT use session default scheme (target must be explicit)
- Still uses session default \`project_path\` if not provided
- Platform-agnostic: accepts destination for sim/device targets too

### \`Sources/Server/XcodeMCPServer.swift\`

- Add \`case checkBuild = "check_build"\` to \`ToolName\` enum
- Register in the \`xc-build\` server group (alongside \`buildMacOS\`)
- Instantiate \`CheckBuildTool\` in \`run()\`

## Files to modify

| File | Change |
|------|--------|
| \`Sources/Core/XcodebuildRunner.swift\` | Add \`buildTarget()\` method |
| \`Sources/Tools/MacOS/CheckBuildTool.swift\` | New tool (follows \`BuildMacOSTool\` pattern) |
| \`Sources/Server/XcodeMCPServer.swift\` | Register \`check_build\` in enum + server |

## Verification

- [x] Build xc-mcp package
- [ ] Test with Thesis project: \`check_build -target DOMTests\` catches missing import
- [ ] Test with Thesis project: \`check_build -target Core\` succeeds
- [ ] Verify error output format matches \`build_macos\`
