import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct CreateGroupTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "create_group",
            description: "Create a new group in the project navigator",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)",
                        ),
                    ]),
                    "group_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the group to create"),
                    ]),
                    "parent_group": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the parent group (optional, defaults to main group)",
                        ),
                    ]),
                    "path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Relative path from parent group to the directory this group represents on disk. Required when the group should correspond to an actual directory (Relative to Group). Typically set to the same value as group_name (e.g., group_name='Models', path='Models'). If omitted, the group will be virtual (no corresponding directory on disk). Note: The directory is NOT created automatically; you must create it beforehand.",
                        ),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("group_name")]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(groupName) = arguments["group_name"]
        else {
            throw MCPError.invalidParams("project_path and group_name are required")
        }

        let parentGroupName: String?

        if case let .string(parent) = arguments["parent_group"] {
            parentGroupName = parent
        } else {
            parentGroupName = nil
        }

        let groupPath: String?
        if case let .string(path) = arguments["path"] { groupPath = path } else { groupPath = nil }

        do {
            // Resolve and validate the project path
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Check if group already exists
            if xcodeproj.pbxproj.groups.contains(where: { $0.name == groupName }) {
                return CallTool.Result(content: [
                    .text(
                        text: "Group '\(groupName)' already exists in project",
                        annotations: nil,
                        _meta: nil,
                    )
                ],)
            }

            // Create new group
            let newGroup = PBXGroup(sourceTree: .group, name: groupName, path: groupPath)
            xcodeproj.pbxproj.add(object: newGroup)

            // Find parent group
            guard let project = try xcodeproj.pbxproj.rootProject(),
                let mainGroup = project.mainGroup
            else { throw MCPError.internalError("Main group not found in project") }

            let parentGroup: PBXGroup

            if let parentGroupName {
                parentGroup = try mainGroup.resolveGroupPath(parentGroupName)
            } else {
                parentGroup = mainGroup
            }

            // Add new group to parent
            parentGroup.children.append(newGroup)

            // When the group represents an on-disk directory, warn if its resolved path (relative
            // to the parent group, not the project root) does not exist. This catches the common
            // mistake of passing a project-root-relative path — e.g. parent_group='Integrations',
            // path='Integrations/GoogleDocs' resolves to 'Integrations/Integrations/GoogleDocs' and
            // renders red in Xcode.
            var warning: String?

            if let groupPath, !groupPath.isEmpty {
                let projectRoot = projectURL.deletingLastPathComponent().path
                let parentAccumulated = OnDiskPath.accumulated(of: parentGroup, in: mainGroup) ?? ""
                let resolved = OnDiskPath.join(parentAccumulated, groupPath)
                let dir = URL(fileURLWithPath: projectRoot)
                    .appendingPathComponent(resolved).path
                var isDirectory: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: dir, isDirectory: &isDirectory)

                if !exists || !isDirectory.boolValue {
                    warning = "Warning: path is relative to the parent group, so this group "
                        + "resolves to '\(resolved)' on disk, which does not exist. "
                        + "If you meant a project-root-relative path, the parent group's "
                        + "path is being prepended (doubling the prefix). Create the "
                        + "directory first, or pass a path relative to the parent group."
                }
            }

            // Save project
            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            var message =
                "Successfully created group '\(groupName)' in \(parentGroupName ?? "main group")"
            if let warning { message += "\n\(warning)" }
            return CallTool.Result(content: [.text(text: message, annotations: nil, _meta: nil)])
        } catch {
            throw MCPError.internalError(
                "Failed to create group in Xcode project: \(error.localizedDescription)",
            )
        }
    }
}
