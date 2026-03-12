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

        let fileName: String?
        if case let .string(f) = arguments["file_name"] {
            fileName = f
        } else {
            fileName = nil
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

            // Find all exception sets for this target
            let matchingIndices: [(
                index: Int,
                set: PBXFileSystemSynchronizedBuildFileExceptionSet,
            )] =
                syncGroup.exceptions?.enumerated().compactMap { index, exception in
                    guard let buildException =
                        exception as? PBXFileSystemSynchronizedBuildFileExceptionSet,
                        buildException.target?.name == targetName
                    else { return nil }
                    return (index, buildException)
                } ?? []

            guard !matchingIndices.isEmpty else {
                throw MCPError.invalidParams(
                    "No exception set found for target '\(targetName)' on synchronized folder '\(folderPath)'",
                )
            }

            if let fileName {
                // Find which exception set contains this file
                guard let match = matchingIndices.first(where: {
                    $0.set.membershipExceptions?.contains(fileName) == true
                }) else {
                    throw MCPError.invalidParams(
                        "File '\(fileName)' not found in exception set for target '\(targetName)'",
                    )
                }

                match.set.membershipExceptions?.removeAll { $0 == fileName }

                // If exception set is now empty, remove it entirely
                if match.set.membershipExceptions?.isEmpty == true {
                    syncGroup.exceptions?.remove(at: match.index)
                    xcodeproj.pbxproj.delete(object: match.set)

                    try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))
                    return CallTool.Result(
                        content: [
                            .text(
                                "Removed '\(fileName)' from exception set for target '\(targetName)' on '\(folderPath)'. Exception set was empty and has been removed.",
                            ),
                        ],
                    )
                }

                try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))
                return CallTool.Result(
                    content: [
                        .text(
                            "Removed '\(fileName)' from exception set for target '\(targetName)' on '\(folderPath)'",
                        ),
                    ],
                )
            } else {
                // Remove all exception sets for this target (handles duplicates)
                for match in matchingIndices.reversed() {
                    syncGroup.exceptions?.remove(at: match.index)
                    xcodeproj.pbxproj.delete(object: match.set)
                }

                try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))
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
}
