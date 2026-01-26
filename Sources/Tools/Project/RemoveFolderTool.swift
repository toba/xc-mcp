import Foundation
import MCP
import PathKit
import XCMCPCore
import XcodeProj

public struct RemoveFolderTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "remove_synchronized_folder",
            description:
                "Remove a synchronized folder reference from an Xcode project (does not delete the folder from disk)",
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
                            "Path of the synchronized folder to remove (e.g., 'Core' or 'Core/Sources')"),
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

        do {
            // Resolve and validate the project path
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(filePath: resolvedProjectPath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Get the root project and main group
            guard let project = try xcodeproj.pbxproj.rootProject(),
                let mainGroup = project.mainGroup
            else {
                throw MCPError.internalError("Main group not found in project")
            }

            // Find and remove the synchronized folder
            var folderRemoved = false
            var removedPath: String?

            func removeFromGroup(_ group: PBXGroup) -> Bool {
                for (index, child) in group.children.enumerated() {
                    if let syncGroup = child as? PBXFileSystemSynchronizedRootGroup {
                        // Match by path
                        if syncGroup.path == folderPath {
                            // Remove any associated exception sets and build files
                            removeAssociatedObjects(for: syncGroup, in: xcodeproj)

                            group.children.remove(at: index)
                            removedPath = syncGroup.path
                            return true
                        }
                    } else if let childGroup = child as? PBXGroup {
                        if removeFromGroup(childGroup) {
                            return true
                        }
                    }
                }
                return false
            }

            folderRemoved = removeFromGroup(mainGroup)

            if folderRemoved {
                try xcodeproj.writePBXProj(
                    path: Path(projectURL.path), outputSettings: PBXOutputSettings())

                return CallTool.Result(
                    content: [
                        .text(
                            "Successfully removed synchronized folder '\(removedPath ?? folderPath)' from project"
                        )
                    ]
                )
            } else {
                return CallTool.Result(
                    content: [
                        .text("Synchronized folder not found in project: \(folderPath)")
                    ]
                )
            }
        } catch {
            throw MCPError.internalError(
                "Failed to remove synchronized folder from Xcode project: \(error.localizedDescription)"
            )
        }
    }

    private func removeAssociatedObjects(
        for syncGroup: PBXFileSystemSynchronizedRootGroup, in xcodeproj: XcodeProj
    ) {
        // Remove any build files referencing this synchronized folder
        let buildFilesToRemove = xcodeproj.pbxproj.buildFiles.filter { buildFile in
            buildFile.file === syncGroup
        }

        for buildFile in buildFilesToRemove {
            // Remove from build phases
            for target in xcodeproj.pbxproj.nativeTargets {
                for phase in target.buildPhases {
                    phase.files?.removeAll { $0 === buildFile }
                }
            }
            xcodeproj.pbxproj.delete(object: buildFile)
        }

        // Remove the synchronized group object itself
        xcodeproj.pbxproj.delete(object: syncGroup)
    }
}
