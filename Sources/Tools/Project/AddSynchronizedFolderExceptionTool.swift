import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct AddSynchronizedFolderExceptionTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "add_synchronized_folder_exception",
            description:
            "Add file membership exceptions to exclude specific files from a target within a synchronized folder",
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
                            "Name of the target to exclude files from",
                        ),
                    ]),
                    "files": .object([
                        "type": .string("array"),
                        "description": .string(
                            "Array of file names to exclude from the target (relative to the synchronized folder)",
                        ),
                        "items": .object([
                            "type": .string("string"),
                        ]),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("folder_path"),
                    .string("target_name"),
                    .string("files"),
                ]),
            ]),
            annotations: .mutation,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(folderPath) = arguments["folder_path"],
              case let .string(targetName) = arguments["target_name"],
              case let .array(filesArray) = arguments["files"]
        else {
            throw MCPError.invalidParams(
                "project_path, folder_path, target_name, and files are required",
            )
        }

        let files = filesArray.compactMap { value -> String? in
            if case let .string(s) = value { return s }
            return nil
        }

        guard !files.isEmpty else {
            throw MCPError.invalidParams("files array must not be empty")
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

            // Check for an existing exception set for this target
            let existingExceptionSet =
                syncGroup.exceptions?.first(where: {
                    guard
                        let ex = $0
                        as? PBXFileSystemSynchronizedBuildFileExceptionSet
                    else { return false }
                    return ex.target?.name == targetName
                }) as? PBXFileSystemSynchronizedBuildFileExceptionSet

            var text = try PBXProjTextEditor.read(
                projectPath: projectURL.path,
            )

            if let existingExceptionSet {
                let existing = Set(
                    existingExceptionSet.membershipExceptions ?? [],
                )
                let newFiles = files.filter { !existing.contains($0) }
                if newFiles.isEmpty {
                    return CallTool.Result(
                        content: [
                            .text(text:
                                "All specified files are already in the exception set for target '\(targetName)' on '\(folderPath)'",
                                annotations: nil, _meta: nil),
                        ],
                    )
                }

                text = try PBXProjTextEditor.addEntriesToArray(
                    text, blockUUID: existingExceptionSet.uuid,
                    field: "membershipExceptions", entries: newFiles,
                )
            } else {
                // Create a new exception set
                let newUUID = PBXProjTextEditor.generateUUID()
                let folderName = syncGroup.path ?? folderPath

                text = try PBXProjTextEditor.insertExceptionSetBlock(
                    text, uuid: newUUID, folderName: folderName,
                    targetName: targetName, targetUUID: target.uuid,
                    membershipExceptions: files,
                )

                let comment =
                    "Exceptions for \"\(folderName)\" folder in \"\(targetName)\" target"
                text = try PBXProjTextEditor.addReference(
                    text, blockUUID: syncGroup.uuid, field: "exceptions",
                    refUUID: newUUID, comment: comment,
                )
            }

            try PBXProjTextEditor.write(text, projectPath: projectURL.path)

            let fileList = files.joined(separator: ", ")
            return CallTool.Result(
                content: [
                    .text(text:
                        "Successfully added membership exceptions for [\(fileList)] in synchronized folder '\(folderPath)' for target '\(targetName)'",
                        annotations: nil, _meta: nil),
                ],
            )
        } catch let error as MCPError {
            throw error
        } catch {
            throw MCPError.internalError(
                "Failed to add synchronized folder exception: \(error.localizedDescription)",
            )
        }
    }
}
