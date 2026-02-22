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
                    .string("project_path"), .string("folder_path"), .string("target_name"),
                ]),
            ]),
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
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(filePath: resolvedProjectPath)
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Find the synchronized folder
            guard let project = try xcodeproj.pbxproj.rootProject(),
                  let mainGroup = project.mainGroup
            else {
                throw MCPError.internalError("Main group not found in project")
            }

            guard let syncGroup = SynchronizedFolderUtility.findSyncGroup(folderPath, in: mainGroup)
            else {
                throw MCPError.invalidParams(
                    "Synchronized folder '\(folderPath)' not found in project",
                )
            }

            // Find the target
            guard
                let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                    $0.name == targetName
                })
            else {
                throw MCPError.invalidParams("Target '\(targetName)' not found in project")
            }

            // Check if target actually references this sync group
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

            // Remove the sync group reference from the target
            target.fileSystemSynchronizedGroups?.removeAll { $0 === syncGroup }
            if target.fileSystemSynchronizedGroups?.isEmpty == true {
                target.fileSystemSynchronizedGroups = nil
            }

            // Clean up exception sets that reference this target
            if let exceptions = syncGroup.exceptions {
                let orphaned = exceptions.filter { exceptionSet in
                    if let buildFileException =
                        exceptionSet as? PBXFileSystemSynchronizedBuildFileExceptionSet
                    {
                        return buildFileException.target === target
                    }
                    return false
                }
                syncGroup.exceptions?.removeAll { exceptionSet in
                    orphaned.contains { $0 === exceptionSet }
                }
                for exceptionSet in orphaned {
                    xcodeproj.pbxproj.delete(object: exceptionSet)
                }
                if syncGroup.exceptions?.isEmpty == true {
                    syncGroup.exceptions = nil
                }
            }

            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

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
