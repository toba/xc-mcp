import Foundation
import MCP
import PathKit
import XCMCPCore
import XcodeProj

public struct RenameGroupTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "rename_group",
            description: "Rename a group in the Xcode project hierarchy",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)"
                        ),
                    ]),
                    "group_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Slash-separated path to the group (e.g. 'Sources/OldName')"
                        ),
                    ]),
                    "new_name": .object([
                        "type": .string("string"),
                        "description": .string("New name for the group"),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("group_path"), .string("new_name"),
                ]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(groupPath) = arguments["group_path"],
            case let .string(newName) = arguments["new_name"]
        else {
            throw MCPError.invalidParams("project_path, group_path, and new_name are required")
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            guard let project = try xcodeproj.pbxproj.rootProject(),
                let mainGroup = project.mainGroup
            else {
                return CallTool.Result(
                    content: [.text("Could not find main group in project")]
                )
            }

            // Walk the path to find the target group
            let pathComponents = groupPath.split(separator: "/").map(String.init)

            var currentGroup: PBXGroup = mainGroup
            for component in pathComponents.dropLast() {
                guard
                    let childGroup = currentGroup.children.compactMap({ $0 as? PBXGroup }).first(
                        where: { $0.name == component || $0.path == component }
                    )
                else {
                    return CallTool.Result(
                        content: [
                            .text(
                                "Group '\(groupPath)' not found in project (failed at '\(component)')"
                            )
                        ]
                    )
                }
                currentGroup = childGroup
            }

            let targetName = pathComponents.last!
            guard
                let targetGroup = currentGroup.children.compactMap({ $0 as? PBXGroup }).first(
                    where: { $0.name == targetName || $0.path == targetName }
                )
            else {
                return CallTool.Result(
                    content: [.text("Group '\(groupPath)' not found in project")]
                )
            }

            // Update group name and path
            let oldName = targetGroup.name ?? targetGroup.path ?? targetName
            targetGroup.name = newName
            if targetGroup.path == oldName {
                targetGroup.path = newName
            }

            // Save project
            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            return CallTool.Result(
                content: [
                    .text("Successfully renamed group '\(oldName)' to '\(newName)'")
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to rename group in Xcode project: \(error.localizedDescription)"
            )
        }
    }
}
