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
                    .string("project_path"), .string("folder_path"), .string("target_name"),
                    .string("files"),
                ]),
            ]),
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

            // Create the exception set
            let exceptionSet = PBXFileSystemSynchronizedBuildFileExceptionSet(
                target: target,
                membershipExceptions: files,
                publicHeaders: nil,
                privateHeaders: nil,
                additionalCompilerFlagsByRelativePath: nil,
                attributesByRelativePath: nil,
            )
            xcodeproj.pbxproj.add(object: exceptionSet)

            // Add exception set to the sync group's exceptions
            if syncGroup.exceptions == nil {
                syncGroup.exceptions = [exceptionSet]
            } else {
                syncGroup.exceptions?.append(exceptionSet)
            }

            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            let fileList = files.joined(separator: ", ")
            return CallTool.Result(
                content: [
                    .text(
                        "Successfully added membership exceptions for [\(fileList)] in synchronized folder '\(folderPath)' for target '\(targetName)'",
                    ),
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
