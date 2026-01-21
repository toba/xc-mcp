import Foundation
import XCMCPCore
import MCP
import PathKit
import XcodeProj

public struct MoveFileTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "move_file",
            description: "Move or rename a file within the project",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)"),
                    ]),
                    "old_path": .object([
                        "type": .string("string"),
                        "description": .string("Current path of the file to move"),
                    ]),
                    "new_path": .object([
                        "type": .string("string"),
                        "description": .string("New path for the file"),
                    ]),
                    "move_on_disk": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Whether to also move the file on disk (optional, defaults to false)"),
                    ]),
                ]),
                "required": .array([
                    .string("project_path"), .string("old_path"), .string("new_path"),
                ]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(oldPath) = arguments["old_path"],
            case let .string(newPath) = arguments["new_path"]
        else {
            throw MCPError.invalidParams("project_path, old_path, and new_path are required")
        }

        let moveOnDisk: Bool
        if case let .bool(move) = arguments["move_on_disk"] {
            moveOnDisk = move
        } else {
            moveOnDisk = false
        }

        do {
            // Resolve and validate the project path
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            // Resolve and validate the old and new file paths
            let resolvedOldPath = try pathUtility.resolvePath(from: oldPath)
            let resolvedNewPath = try pathUtility.resolvePath(from: newPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            let oldFileName = URL(fileURLWithPath: resolvedOldPath).lastPathComponent
            let newFileName = URL(fileURLWithPath: resolvedNewPath).lastPathComponent

            // Use relative paths from project for comparison and updates
            let oldRelativePath =
                pathUtility.makeRelativePath(from: resolvedOldPath) ?? resolvedOldPath
            let newRelativePath =
                pathUtility.makeRelativePath(from: resolvedNewPath) ?? resolvedNewPath

            var fileMoved = false

            // Find and update file references
            for fileRef in xcodeproj.pbxproj.fileReferences {
                if fileRef.path == oldRelativePath || fileRef.path == oldPath
                    || fileRef.name == oldFileName || fileRef.path == oldFileName
                {
                    // Update the file reference
                    fileRef.path = newRelativePath
                    fileRef.name = newFileName
                    fileMoved = true
                }
            }

            if fileMoved {
                try xcodeproj.write(path: Path(projectURL.path))

                // Optionally move on disk
                if moveOnDisk {
                    let oldURL = URL(fileURLWithPath: resolvedOldPath)
                    let newURL = URL(fileURLWithPath: resolvedNewPath)

                    // Create parent directory if needed
                    let newParentDir = newURL.deletingLastPathComponent()
                    if !FileManager.default.fileExists(atPath: newParentDir.path) {
                        try FileManager.default.createDirectory(
                            at: newParentDir, withIntermediateDirectories: true)
                    }

                    // Move the file
                    if FileManager.default.fileExists(atPath: oldURL.path) {
                        try FileManager.default.moveItem(at: oldURL, to: newURL)
                    }
                }

                return CallTool.Result(
                    content: [
                        .text("Successfully moved \(oldFileName) to \(newRelativePath)")
                    ]
                )
            } else {
                return CallTool.Result(
                    content: [
                        .text("File not found in project: \(oldFileName)")
                    ]
                )
            }
        } catch {
            throw MCPError.internalError(
                "Failed to move file in Xcode project: \(error.localizedDescription)")
        }
    }
}
