import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct RemoveSynchronizedFolderExceptionTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "remove_synchronized_folder_exception",
            description:
            "Remove a file from an exception set, or remove an entire exception set from a synchronized folder",
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
                            "Name of the target whose exception set to modify or remove",
                        ),
                    ]),
                    "file_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional: specific file to remove from the exception set. If omitted, the entire exception set for the target is removed.",
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

        let fileName: String?
        if case let .string(f) = arguments["file_name"] {
            fileName = f
        } else {
            fileName = nil
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
                let resolvedTarget = xcodeproj.pbxproj.nativeTargets.first(
                    where: { $0.name == targetName },
                )
            else {
                throw MCPError.invalidParams(
                    "Target '\(targetName)' not found in project",
                )
            }

            // Find the exception set for this target on this sync group
            let exceptionSet = findExceptionSet(
                syncGroup: syncGroup, target: resolvedTarget,
                targetName: targetName, pbxproj: xcodeproj.pbxproj,
            )

            guard let exceptionSet else {
                throw MCPError.invalidParams(
                    "No exception set found for target '\(targetName)' on synchronized folder '\(folderPath)'",
                )
            }

            let exceptionUUID = exceptionSet.uuid
            let syncGroupUUID = syncGroup.uuid

            // Read the raw pbxproj text — all edits happen here
            var text = try PBXProjTextEditor.read(
                projectPath: projectURL.path,
            )

            if let fileName {
                guard
                    exceptionSet.membershipExceptions?.contains(fileName)
                    == true
                else {
                    throw MCPError.invalidParams(
                        "File '\(fileName)' not found in exception set for target '\(targetName)'",
                    )
                }

                let (edited, remaining) =
                    try PBXProjTextEditor.removeEntriesFromArray(
                        text, blockUUID: exceptionUUID,
                        field: "membershipExceptions",
                        entries: [fileName],
                    )
                text = edited

                if remaining == 0 {
                    // Exception set is empty — remove the block and its reference
                    text = try PBXProjTextEditor.removeBlock(
                        text, uuid: exceptionUUID,
                    )
                    text = try PBXProjTextEditor.removeReference(
                        text, blockUUID: syncGroupUUID,
                        field: "exceptions", refUUID: exceptionUUID,
                    )

                    try PBXProjTextEditor.write(
                        text, projectPath: projectURL.path,
                    )
                    return CallTool.Result(
                        content: [
                            .text(
                                "Removed '\(fileName)' from exception set for target '\(targetName)' on '\(folderPath)'. Exception set was empty and has been removed.",
                            ),
                        ],
                    )
                }

                try PBXProjTextEditor.write(
                    text, projectPath: projectURL.path,
                )
                return CallTool.Result(
                    content: [
                        .text(
                            "Removed '\(fileName)' from exception set for target '\(targetName)' on '\(folderPath)'",
                        ),
                    ],
                )
            } else {
                // Remove the entire exception set
                text = try PBXProjTextEditor.removeBlock(
                    text, uuid: exceptionUUID,
                )
                text = try PBXProjTextEditor.removeReference(
                    text, blockUUID: syncGroupUUID,
                    field: "exceptions", refUUID: exceptionUUID,
                )

                try PBXProjTextEditor.write(
                    text, projectPath: projectURL.path,
                )
                return CallTool.Result(
                    content: [
                        .text(
                            "Removed exception set for target '\(targetName)' from synchronized folder '\(folderPath)'",
                        ),
                    ],
                )
            }
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to remove synchronized folder exception: \(error.localizedDescription)",
            )
        }
    }

    /// Find the exception set for a target on a sync group.
    /// Uses identity match first, then falls back to name/UUID match.
    private func findExceptionSet(
        syncGroup: PBXFileSystemSynchronizedRootGroup,
        target: PBXNativeTarget,
        targetName: String,
        pbxproj: PBXProj,
    ) -> PBXFileSystemSynchronizedBuildFileExceptionSet? {
        // Primary: from the sync group's resolved exceptions
        if let match = syncGroup.exceptions?.first(where: {
            guard
                let ex = $0
                as? PBXFileSystemSynchronizedBuildFileExceptionSet
            else { return false }
            return ex.target === target || ex.target?.name == targetName
        }) as? PBXFileSystemSynchronizedBuildFileExceptionSet {
            return match
        }

        // Fallback: search all exception sets by target UUID
        return pbxproj.fileSystemSynchronizedBuildFileExceptionSets
            .first { ex in
                ex.target === target || ex.target?.name == targetName
                    || ex.target?.uuid == target.uuid
            }
    }
}
