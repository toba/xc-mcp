import Foundation
import MCP
import PathKit
import XCMCPCore
import XcodeProj

public struct RemoveGroupTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "remove_group",
            description: "Remove a group from the project navigator",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)"
                        ),
                    ]),
                    "group_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name or path of the group to remove (e.g., 'Models' or 'Sources/Models')"
                        ),
                    ]),
                    "recursive": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "If true, also remove all child groups and file references. If false (default), fails when the group has children."
                        ),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("group_name")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(groupName) = arguments["group_name"]
        else {
            throw MCPError.invalidParams("project_path and group_name are required")
        }

        let recursive: Bool
        if case let .bool(r) = arguments["recursive"] {
            recursive = r
        } else {
            recursive = false
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(filePath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            guard let project = try xcodeproj.pbxproj.rootProject(),
                let mainGroup = project.mainGroup
            else {
                throw MCPError.internalError("Main group not found in project")
            }

            // Walk the path to find the target group and its parent
            let pathComponents = groupName.split(separator: "/").map(String.init)

            var parentGroup: PBXGroup = mainGroup
            for component in pathComponents.dropLast() {
                guard
                    let childGroup = parentGroup.children.compactMap({ $0 as? PBXGroup }).first(
                        where: { $0.name == component || $0.path == component }
                    )
                else {
                    return CallTool.Result(
                        content: [
                            .text(
                                "Group '\(groupName)' not found in project (failed at '\(component)')"
                            )
                        ]
                    )
                }
                parentGroup = childGroup
            }

            let targetName = pathComponents.last!
            guard
                let targetGroup = parentGroup.children.compactMap({ $0 as? PBXGroup }).first(
                    where: { $0.name == targetName || $0.path == targetName }
                )
            else {
                return CallTool.Result(
                    content: [.text("Group '\(groupName)' not found in project")]
                )
            }

            // Check for children when not recursive
            if !recursive && !targetGroup.children.isEmpty {
                return CallTool.Result(
                    content: [
                        .text(
                            "Group '\(groupName)' has \(targetGroup.children.count) children. Use recursive=true to remove it and all its contents."
                        )
                    ]
                )
            }

            // Remove children recursively
            if recursive {
                removeChildren(of: targetGroup, from: xcodeproj.pbxproj)
            }

            // Remove from parent
            parentGroup.children.removeAll { $0 === targetGroup }

            // Delete the group object
            xcodeproj.pbxproj.delete(object: targetGroup)

            // Save project
            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            return CallTool.Result(
                content: [
                    .text("Successfully removed group '\(groupName)' from project")
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to remove group from Xcode project: \(error.localizedDescription)"
            )
        }
    }

    private func removeChildren(of group: PBXGroup, from pbxproj: PBXProj) {
        for child in group.children {
            if let childGroup = child as? PBXGroup {
                removeChildren(of: childGroup, from: pbxproj)
            }
            pbxproj.delete(object: child)
        }
        group.children.removeAll()
    }
}
