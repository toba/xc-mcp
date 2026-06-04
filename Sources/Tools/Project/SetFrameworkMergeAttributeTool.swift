import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// Toggles the per-link-phase `Merge` PBXBuildFile attribute on an entry inside a target's
/// `PBXFrameworksBuildPhase`. This is the per-library flag Xcode writes when the user checks
/// "Merge" in the Frameworks build phase UI; combined with `MERGED_BINARY_TYPE = manual` on
/// the consumer target, it selects which dependencies actually merge.
public struct SetFrameworkMergeAttributeTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
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
                        "description": .string("Name of the target whose Frameworks phase to modify"),
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
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(targetName) = arguments["target_name"],
              case let .string(frameworkName) = arguments["framework_name"],
              case let .bool(merge) = arguments["merge"]
        else {
            throw MCPError.invalidParams(
                "project_path, target_name, framework_name, and merge are required",
            )
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            guard
                let target = xcodeproj.pbxproj.nativeTargets.first(where: { $0.name == targetName })
            else {
                return CallTool.Result(content: [
                    .text(
                        text: "Target '\(targetName)' not found in project",
                        annotations: nil, _meta: nil,
                    ),
                ])
            }

            let phases = target.buildPhases.compactMap { $0 as? PBXFrameworksBuildPhase }
            if phases.isEmpty {
                return CallTool.Result(content: [
                    .text(
                        text: "Target '\(targetName)' has no PBXFrameworksBuildPhase",
                        annotations: nil, _meta: nil,
                    ),
                ])
            }

            // Collect every match across all frameworks phases so we can refuse ambiguous edits.
            var matches: [PBXBuildFile] = []
            for phase in phases {
                for buildFile in phase.files ?? [] where Self.matches(buildFile, name: frameworkName) {
                    matches.append(buildFile)
                }
            }

            if matches.isEmpty {
                return CallTool.Result(content: [
                    .text(
                        text:
                        "No frameworks-phase entry matching '\(frameworkName)' in target '\(targetName)'. Use list_frameworks_phase to see available entries.",
                        annotations: nil, _meta: nil,
                    ),
                ])
            }

            if matches.count > 1 {
                return CallTool.Result(content: [
                    .text(
                        text:
                        "Ambiguous framework name '\(frameworkName)' in target '\(targetName)' — \(matches.count) entries match. Use a more specific identifier.",
                        annotations: nil, _meta: nil,
                    ),
                ])
            }

            let buildFile = matches[0]
            let (changed, beforeAttrs, afterAttrs) = Self.applyMerge(merge, to: buildFile)

            if !changed {
                return CallTool.Result(content: [
                    .text(
                        text:
                        "'\(frameworkName)' already has merge=\(merge) (ATTRIBUTES=\(beforeAttrs)). No changes made.",
                        annotations: nil, _meta: nil,
                    ),
                ])
            }

            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            return CallTool.Result(content: [
                .text(
                    text:
                    "Set merge=\(merge) on '\(frameworkName)' in target '\(targetName)' (ATTRIBUTES \(beforeAttrs) → \(afterAttrs))",
                    annotations: nil, _meta: nil,
                ),
            ])
        } catch {
            throw MCPError.internalError(
                "Failed to set framework merge attribute: \(error.localizedDescription)",
            )
        }
    }

    static func matches(_ buildFile: PBXBuildFile, name: String) -> Bool {
        if let product = buildFile.product {
            if product.productName == name { return true }
        }
        if let fileElement = buildFile.file {
            if let proxy = fileElement as? PBXReferenceProxy {
                if proxy.path == name || proxy.name == name { return true }
                if let p = proxy.path, (p as NSString).lastPathComponent == name { return true }
            }
            if fileElement.path == name || fileElement.name == name { return true }
            if let p = fileElement.path, (p as NSString).lastPathComponent == name { return true }
        }
        return false
    }

    /// Returns (changed, beforeAttributesDescription, afterAttributesDescription).
    static func applyMerge(
        _ merge: Bool,
        to buildFile: PBXBuildFile,
    ) -> (Bool, String, String) {
        var settings = buildFile.settings ?? [:]
        var attrs: [String]
        if case let .array(existing) = settings["ATTRIBUTES"] {
            attrs = existing
        } else if case let .string(single) = settings["ATTRIBUTES"] {
            attrs = [single]
        } else {
            attrs = []
        }

        let beforeDesc = attrs.isEmpty ? "(none)" : "[\(attrs.joined(separator: ", "))]"
        let hasMerge = attrs.contains("Merge")

        if merge {
            if hasMerge {
                return (false, beforeDesc, beforeDesc)
            }
            attrs.append("Merge")
        } else {
            if !hasMerge {
                return (false, beforeDesc, beforeDesc)
            }
            attrs.removeAll { $0 == "Merge" }
        }

        if attrs.isEmpty {
            settings.removeValue(forKey: "ATTRIBUTES")
        } else {
            settings["ATTRIBUTES"] = .array(attrs)
        }
        buildFile.settings = settings.isEmpty ? nil : settings

        let afterDesc = attrs.isEmpty ? "(none)" : "[\(attrs.joined(separator: ", "))]"
        return (true, beforeDesc, afterDesc)
    }
}
