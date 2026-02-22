import Foundation
import MCP
import PathKit
import XCMCPCore
import XcodeProj

public struct AddTargetToSynchronizedFolderTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "add_target_to_synchronized_folder",
            description:
                "Add an existing synchronized folder to a target's file system synchronized groups (for sharing a folder between multiple targets)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)"
                        ),
                    ]),
                    "folder_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path of the synchronized folder within the project (e.g., 'Sources' or 'App/Sources')"
                        ),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the target to add the synchronized folder to"
                        ),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("folder_path"), .string("target_name"),
                ]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(folderPath) = arguments["folder_path"],
            case let .string(targetName) = arguments["target_name"]
        else {
            throw MCPError.invalidParams(
                "project_path, folder_path, and target_name are required"
            )
        }

        do {
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(filePath: resolvedProjectPath)
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Find the synchronized folder by walking the group hierarchy
            guard let project = try xcodeproj.pbxproj.rootProject(),
                let mainGroup = project.mainGroup
            else {
                throw MCPError.internalError("Main group not found in project")
            }

            guard let syncGroup = SynchronizedFolderUtility.findSyncGroup(folderPath, in: mainGroup)
            else {
                throw MCPError.invalidParams(
                    "Synchronized folder '\(folderPath)' not found in project"
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

            // Check if already added (idempotency)
            if let existing = target.fileSystemSynchronizedGroups,
                existing.contains(where: { $0 === syncGroup })
            {
                return CallTool.Result(
                    content: [
                        .text(
                            "Synchronized folder '\(folderPath)' is already in target '\(targetName)'"
                        )
                    ]
                )
            }

            // Add the sync group to the target
            if target.fileSystemSynchronizedGroups == nil {
                target.fileSystemSynchronizedGroups = [syncGroup]
            } else {
                target.fileSystemSynchronizedGroups?.append(syncGroup)
            }

            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            return CallTool.Result(
                content: [
                    .text(
                        "Successfully added synchronized folder '\(folderPath)' to target '\(targetName)'"
                    )
                ]
            )
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to add target to synchronized folder: \(error.localizedDescription)"
            )
        }
    }
}
