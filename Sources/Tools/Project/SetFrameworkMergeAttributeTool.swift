import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// Toggles the per-link-phase `Merge` PBXBuildFile attribute on an entry inside a target's
/// `PBXFrameworksBuildPhase`. This is the per-library flag Xcode writes when the user checks
/// "Merge" in the Frameworks build phase UI; combined with `MERGED_BINARY_TYPE = manual` on the
/// consumer target, it selects which dependencies actually merge.
public struct SetFrameworkMergeAttributeTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "set_framework_merge_attribute",
            description:
                "Set or clear the per-library 'Merge' PBXBuildFile attribute on an entry in a target's PBXFrameworksBuildPhase. This is the flag MERGED_BINARY_TYPE=manual uses to decide which mergeable dependencies merge. Matches against productName (SPM products), PBXReferenceProxy name/path (cross-project), or file path's last component / name (local frameworks). No-op (with a clear message) if the attribute is already in the requested state.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)",
                        ),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the target whose Frameworks phase to modify"),
                    ]),
                    "framework_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Identifier of the framework entry: SPM productName, cross-project PBXReferenceProxy name/path, or local framework path/last-component (e.g. 'MyLib', 'MyLib.framework')",
                        ),
                    ]),
                    "merge": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "true to add 'Merge' to ATTRIBUTES; false to remove it",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("target_name"),
                    .string("framework_name"), .string("merge"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard let projectPath = arguments.getString("project_path"),
              let targetName = arguments.getString("target_name"),
              let frameworkName = arguments.getString("framework_name"),
              let merge = arguments.getOptionalBool("merge")
        else {
            throw MCPError.invalidParams(
                "project_path, target_name, framework_name, and merge are required",
            )
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)
            let projectFilePath = Path(projectURL.path)

            let preimage = PBXProjWriter.preimage(of: projectFilePath)
            let xcodeproj = try XcodeProj(path: projectFilePath)

            guard let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                $0.name == targetName
            }) else {
                return CallTool.Result.text("Target '\(targetName)' not found in project")
            }

            let phases = target.buildPhases.compactMap { $0 as? PBXFrameworksBuildPhase }

            if phases.isEmpty {
                return CallTool.Result.text("Target '\(targetName)' has no PBXFrameworksBuildPhase")
            }

            // Collect every match across all frameworks phases so we can refuse ambiguous edits.
            let matches = phases.flatMap { phase in
                (phase.files ?? []).filter { CopyFilesPhaseEntry.matches($0, name: frameworkName) }
            }

            if matches.isEmpty {
                return CallTool.Result.text(
                    "No frameworks-phase entry matching '\(frameworkName)' in target '\(targetName)'. Use list_frameworks_phase to see available entries."
                )
            }

            if matches.count > 1 {
                return CallTool.Result.text(
                    "Ambiguous framework name '\(frameworkName)' in target '\(targetName)' — \(matches.count) entries match. Use a more specific identifier."
                )
            }

            let buildFile = matches[0]
            let (changed, beforeAttrs, afterAttrs) = Self.applyMerge(merge, to: buildFile)

            if !changed {
                return CallTool.Result.text(
                    "'\(frameworkName)' already has merge=\(merge) (ATTRIBUTES=\(beforeAttrs)). No changes made."
                )
            }

            try PBXProjWriter.write(xcodeproj, to: projectFilePath, expectedPreimage: preimage)

            return CallTool.Result.text(
                "Set merge=\(merge) on '\(frameworkName)' in target '\(targetName)' (ATTRIBUTES \(beforeAttrs) → \(afterAttrs))"
            )
        } catch {
            throw try error.asMCPError()
        }
    }

    static func applyMerge(
        _ merge: Bool,
        to buildFile: PBXBuildFile,
    ) -> (changed: Bool, before: String, after: String) {
        var attrs = BuildFileAttributes.read(buildFile)
        let beforeDesc = BuildFileAttributes.describe(attrs)
        let hasMerge = attrs.contains("Merge")

        if merge {
            if hasMerge { return (false, beforeDesc, beforeDesc) }
            attrs.append("Merge")
        } else {
            if !hasMerge { return (false, beforeDesc, beforeDesc) }
            attrs.removeAll { $0 == "Merge" }
        }

        _ = BuildFileAttributes.write(attrs, to: buildFile)
        return (true, beforeDesc, BuildFileAttributes.describe(attrs))
    }
}
