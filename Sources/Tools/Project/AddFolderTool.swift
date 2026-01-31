import Foundation
import MCP
import PathKit
import XCMCPCore
import XcodeProj

public struct AddFolderTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "add_synchronized_folder",
            description: "Add a synchronized folder reference to an Xcode project",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)"),
                    ]),
                    "folder_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the folder to add (relative to project root or absolute)"),
                    ]),
                    "group_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the group to add the folder to (optional, defaults to main group)"
                        ),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the target to add the folder to (optional)"),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("folder_path")]),
            ])
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
            case let .string(folderPath) = arguments["folder_path"]
        else {
            throw MCPError.invalidParams("project_path and folder_path are required")
        }

        let groupName: String?
        if case let .string(group) = arguments["group_name"] {
            groupName = group
        } else {
            groupName = nil
        }

        let targetName: String?
        if case let .string(target) = arguments["target_name"] {
            targetName = target
        } else {
            targetName = nil
        }

        do {
            // Resolve and validate the project path
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(filePath: resolvedProjectPath)

            // Resolve and validate the folder path
            let resolvedFolderPath = try pathUtility.resolvePath(from: folderPath)

            // Verify that the path is actually a directory
            var isDirectory: ObjCBool = false
            if !FileManager.default.fileExists(
                atPath: resolvedFolderPath, isDirectory: &isDirectory)
            {
                throw MCPError.invalidParams("Folder does not exist at path: \(folderPath)")
            }
            if !isDirectory.boolValue {
                throw MCPError.invalidParams("Path is not a directory: \(folderPath)")
            }

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Find the group to add the folder to (must be done before calculating relative path)
            let targetGroup: PBXGroup
            if let groupName {
                // Support path-based lookup (e.g., "Integrations/BibTeX")
                let pathComponents = groupName.split(separator: "/").map(String.init)

                guard let project = try xcodeproj.pbxproj.rootProject(),
                    let mainGroup = project.mainGroup
                else {
                    throw MCPError.internalError("Main group not found in project")
                }

                var currentGroup: PBXGroup = mainGroup
                for component in pathComponents {
                    if let childGroup = currentGroup.children.compactMap({ $0 as? PBXGroup }).first(
                        where: { $0.name == component || $0.path == component })
                    {
                        currentGroup = childGroup
                    } else {
                        throw MCPError.invalidParams(
                            "Group '\(groupName)' not found in project (failed at '\(component)')")
                    }
                }
                targetGroup = currentGroup
            } else {
                // Use main group
                guard let project = try xcodeproj.pbxproj.rootProject(),
                    let mainGroup = project.mainGroup
                else {
                    throw MCPError.internalError("Main group not found in project")
                }
                targetGroup = mainGroup
            }

            // Create file system synchronized root group
            let folderName = URL(filePath: resolvedFolderPath).lastPathComponent

            // Calculate the path relative to the parent group, not project root
            // Since sourceTree is .group, Xcode resolves paths relative to the parent group
            let projectRoot = projectURL.deletingLastPathComponent().path
            let groupFullPath: String
            if let groupPath = try targetGroup.fullPath(sourceRoot: projectRoot) {
                groupFullPath = groupPath
            } else {
                groupFullPath = projectRoot
            }

            // Make the folder path relative to the group's location
            let relativePath: String
            if resolvedFolderPath.hasPrefix(groupFullPath + "/") {
                // Folder is inside the group's directory - use relative path from group
                relativePath = String(resolvedFolderPath.dropFirst(groupFullPath.count + 1))
            } else if resolvedFolderPath == groupFullPath {
                // Folder is the group's directory itself
                relativePath = "."
            } else {
                // Folder is not inside the group - use path relative to project root
                relativePath =
                    pathUtility.makeRelativePath(from: resolvedFolderPath) ?? resolvedFolderPath
            }

            let folderReference = PBXFileSystemSynchronizedRootGroup(
                sourceTree: .group,
                path: relativePath,
                name: folderName
            )
            xcodeproj.pbxproj.add(object: folderReference)

            // Add folder to group
            targetGroup.children.append(folderReference)

            // Add folder to target if specified
            if let targetName {
                guard
                    let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                        $0.name == targetName
                    })
                else {
                    throw MCPError.invalidParams("Target '\(targetName)' not found in project")
                }

                // Add synchronized group to target's fileSystemSynchronizedGroups
                // This tells Xcode to automatically include files from this folder in the target
                if target.fileSystemSynchronizedGroups == nil {
                    target.fileSystemSynchronizedGroups = [folderReference]
                } else {
                    target.fileSystemSynchronizedGroups?.append(folderReference)
                }
            }

            // Write project
            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            let targetInfo = targetName != nil ? " to target '\(targetName!)'" : ""
            let groupInfo = groupName != nil ? " in group '\(groupName!)'" : ""

            return CallTool.Result(
                content: [
                    .text(
                        "Successfully added folder reference '\(folderName)'\(targetInfo)\(groupInfo)"
                    )
                ]
            )
        } catch {
            throw MCPError.internalError(
                "Failed to add folder to Xcode project: \(error.localizedDescription)")
        }
    }
}
