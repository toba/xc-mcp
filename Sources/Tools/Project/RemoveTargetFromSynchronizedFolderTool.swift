import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct RemoveTargetFromSynchronizedFolderTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "remove_target_from_synchronized_folder",
            description:
            "Remove a target's reference to a synchronized folder (unlink a shared folder from a target)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)",
                        ),
                    ]),
                    "folder_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path of the synchronized folder within the project (e.g., 'Sources' or 'App/Sources')",
                        ),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the target to unlink from the synchronized folder",
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("folder_path"),
                    .string("target_name"),
                ]),
            ]),
            annotations: .destructive,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(folderPath) = arguments["folder_path"],
              case let .string(targetName) = arguments["target_name"]
        else {
            throw MCPError.invalidParams(
                "project_path, folder_path, and target_name are required",
            )
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(
                from: projectPath,
            )
            let projectURL = URL(filePath: resolvedProjectPath)
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            guard let project = try xcodeproj.pbxproj.rootProject(),
                  let mainGroup = project.mainGroup
            else {
                throw MCPError.internalError("Main group not found in project")
            }

            guard
                let syncGroup = SynchronizedFolderUtility.findSyncGroup(
                    folderPath, in: mainGroup,
                )
            else {
                throw MCPError.invalidParams(
                    "Synchronized folder '\(folderPath)' not found in project",
                )
            }

            guard
                let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                    $0.name == targetName
                })
            else {
                throw MCPError.invalidParams(
                    "Target '\(targetName)' not found in project",
                )
            }

            guard let syncGroups = target.fileSystemSynchronizedGroups,
                  syncGroups.contains(where: { $0 === syncGroup })
            else {
                return CallTool.Result(
                    content: [
                        .text(
                            "Target '\(targetName)' does not reference synchronized folder '\(folderPath)'",
                        ),
                    ],
                )
            }

            var text = try PBXProjTextEditor.read(
                projectPath: projectURL.path,
            )

            // Remove the sync group reference from the target
            text = try PBXProjTextEditor.removeReference(
                text, blockUUID: target.uuid,
                field: "fileSystemSynchronizedGroups",
                refUUID: syncGroup.uuid,
            )

            // Clean up orphaned exception sets for this target
            let orphaned =
                (syncGroup.exceptions ?? []).compactMap {
                    $0 as? PBXFileSystemSynchronizedBuildFileExceptionSet
                }.filter { $0.target === target }

            for ex in orphaned {
                text = try PBXProjTextEditor.removeBlock(
                    text, uuid: ex.uuid,
                )
                text = try PBXProjTextEditor.removeReference(
                    text, blockUUID: syncGroup.uuid,
                    field: "exceptions", refUUID: ex.uuid,
                )
            }

            try PBXProjTextEditor.write(text, projectPath: projectURL.path)

            return CallTool.Result(
                content: [
                    .text(
                        "Successfully removed target '\(targetName)' from synchronized folder '\(folderPath)'",
                    ),
                ],
            )
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to remove target from synchronized folder: \(error.localizedDescription)",
            )
        }
    }
}
