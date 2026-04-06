import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct RemoveFileTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    public func tool() -> Tool {
        Tool(
            name: "remove_file",
            description: "Remove a file from the Xcode project",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "project_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the .xcodeproj file (relative to current directory)",
                        ),
                    ]),
                    "file_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the file to remove (relative to project root or absolute)",
                        ),
                    ]),
                    "remove_from_disk": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Whether to also delete the file from disk (optional, defaults to false)",
                        ),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("file_path")]),
            ]),
            annotations: .destructive,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(filePath) = arguments["file_path"]
        else {
            throw MCPError.invalidParams("project_path and file_path are required")
        }

        let removeFromDisk: Bool
        if case let .bool(remove) = arguments["remove_from_disk"] {
            removeFromDisk = remove
        } else {
            removeFromDisk = false
        }

        do {
            // Resolve and validate the project path
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)
            let projectRoot = Path(projectURL.deletingLastPathComponent().path)

            // Resolve and validate the file path
            let resolvedFilePath = try pathUtility.resolvePath(from: filePath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            let fileName = URL(fileURLWithPath: resolvedFilePath).lastPathComponent

            /// Check whether a file reference matches the requested path by
            /// computing its full path relative to the project source root.
            func matchesRequestedFile(_ fileRef: PBXFileReference) -> Bool {
                if let fullPath = try? fileRef.fullPath(sourceRoot: projectRoot) {
                    return fullPath.string == resolvedFilePath
                        || resolvedFilePath.hasSuffix(fullPath.string)
                }
                return false
            }

            // --- Phase 1: Identify all UUIDs to remove using XcodeProj (read-only) ---

            struct BuildFileRemoval {
                let buildFileUUID: String
                let phaseUUID: String
                let targetName: String
            }

            var removals: [BuildFileRemoval] = []
            var fileRefUUID: String?

            // Find build files referencing this file in all targets
            for target in xcodeproj.pbxproj.nativeTargets {
                for phase in target.buildPhases {
                    if let files = phase.files {
                        for buildFile in files {
                            if let fileRef = buildFile.file as? PBXFileReference,
                               matchesRequestedFile(fileRef)
                            {
                                removals.append(BuildFileRemoval(
                                    buildFileUUID: buildFile.uuid,
                                    phaseUUID: phase.uuid,
                                    targetName: target.name,
                                ))
                                fileRefUUID = fileRef.uuid
                            }
                        }
                    }
                }
            }

            // Find parent group containing the file reference
            var parentGroupUUID: String?

            func findParentGroup(_ group: PBXGroup) -> PBXGroup? {
                for child in group.children {
                    if let fileRef = child as? PBXFileReference,
                       matchesRequestedFile(fileRef)
                    {
                        fileRefUUID = fileRef.uuid
                        return group
                    }
                    if let childGroup = child as? PBXGroup,
                       let found = findParentGroup(childGroup)
                    {
                        return found
                    }
                }
                return nil
            }

            if let mainGroup = xcodeproj.pbxproj.rootObject?.mainGroup {
                if let group = findParentGroup(mainGroup) {
                    parentGroupUUID = group.uuid
                }
            }

            guard !removals.isEmpty || parentGroupUUID != nil else {
                return CallTool.Result(
                    content: [
                        .text(
                            text: "File not found in project: \(fileName)",
                            annotations: nil,
                            _meta: nil,
                        ),
                    ],
                )
            }

            // --- Phase 2: Text-based edits ---
            var text = try PBXProjTextEditor.read(projectPath: resolvedProjectPath)

            // Remove from build phases and delete build file blocks
            for removal in removals {
                text = try PBXProjTextEditor.removeReference(
                    text, blockUUID: removal.phaseUUID, field: "files",
                    refUUID: removal.buildFileUUID,
                )
                text = try PBXProjTextEditor.removeBlock(text, uuid: removal.buildFileUUID)
            }

            // Remove from parent group and delete file reference block
            if let refUUID = fileRefUUID, let groupUUID = parentGroupUUID {
                text = try PBXProjTextEditor.removeReference(
                    text, blockUUID: groupUUID, field: "children",
                    refUUID: refUUID,
                )
                text = try PBXProjTextEditor.removeBlock(text, uuid: refUUID)
            }

            try PBXProjTextEditor.write(text, projectPath: resolvedProjectPath)

            // Optionally remove from disk
            if removeFromDisk {
                let fileURL = URL(fileURLWithPath: resolvedFilePath)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
            }

            let removedFromTargets = removals.map(\.targetName)
            return CallTool.Result(
                content: [
                    .text(text:
                        "Successfully removed \(fileName) from project. Removed from targets: \(removedFromTargets.joined(separator: ", "))",
                        annotations: nil, _meta: nil),
                ],
            )
        } catch {
            throw MCPError.internalError(
                "Failed to remove file from Xcode project: \(error.localizedDescription)",
            )
        }
    }
}
