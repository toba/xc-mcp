import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

/// MCP tool for adding files to an Xcode project.
///
/// Adds a file reference to the project and optionally adds it to a specific
/// target's build phases based on the file type (source, header, or resource).
public struct AddFileTool: Sendable {
    private let pathUtility: PathUtility

    /// Creates a new AddFileTool instance.
    ///
    /// - Parameter pathUtility: Utility for resolving and validating paths.
    public init(pathUtility: PathUtility) {
        self.pathUtility = pathUtility
    }

    /// Returns the MCP tool definition.
    public func tool() -> Tool {
        Tool(
            name: "add_file",
            description: "Add a file to an Xcode project",
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
                            "Path to the file to add (relative to project root or absolute)",
                        ),
                    ]),
                    "group_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Group to add the file to, supports slash-separated paths (e.g. 'Components/TableView'). Optional, defaults to main group.",
                        ),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string("Name of the target to add the file to (optional)"),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("file_path")]),
            ]),
            annotations: .mutation,
        )
    }

    /// Executes the tool with the given arguments.
    ///
    /// - Parameter arguments: Dictionary containing project_path, file_path, and optional group_name and target_name.
    /// - Returns: The result containing success message.
    /// - Throws: MCPError if required parameters are missing or file addition fails.
    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard case let .string(projectPath) = arguments["project_path"],
              case let .string(filePath) = arguments["file_path"]
        else {
            throw MCPError.invalidParams("project_path and file_path are required")
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
            let projectURL = URL(fileURLWithPath: resolvedProjectPath)

            // Resolve and validate the file path
            let resolvedFilePath = try pathUtility.resolvePath(from: filePath)

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Find the group to add the file to
            guard let project = try xcodeproj.pbxproj.rootProject(),
                  let mainGroup = project.mainGroup
            else {
                throw MCPError.internalError("Main group not found in project")
            }

            let targetGroup: PBXGroup
            if let groupName {
                targetGroup = try mainGroup.resolveGroupPath(groupName)
            } else {
                targetGroup = mainGroup
            }

            let fileName = URL(fileURLWithPath: resolvedFilePath).lastPathComponent
            let projectRoot = projectURL.deletingLastPathComponent().path
            let groupFullPath: String
            if let gp = try targetGroup.fullPath(sourceRoot: projectRoot) {
                groupFullPath = gp
            } else {
                groupFullPath = projectRoot
            }

            // Check for existing file reference with the same resolved path to avoid duplicates
            let existingFileRef = xcodeproj.pbxproj.fileReferences.first { ref in
                guard let refFullPath = try? ref.fullPath(sourceRoot: projectRoot) else {
                    return false
                }
                return refFullPath == resolvedFilePath
            }

            let fileReference: PBXFileReference
            if let existingFileRef {
                fileReference = existingFileRef
            } else {
                // Compute path and sourceTree based on whether the file is under the group
                let sourceTree: PBXSourceTree
                let relativePath: String
                if resolvedFilePath.hasPrefix(groupFullPath + "/") {
                    // File is inside the group's directory — use path relative to group
                    sourceTree = .group
                    relativePath = String(resolvedFilePath.dropFirst(groupFullPath.count + 1))
                } else if resolvedFilePath.hasPrefix(projectRoot + "/") {
                    // File is outside the group but inside the project — use sourceRoot
                    sourceTree = .sourceRoot
                    relativePath = String(resolvedFilePath.dropFirst(projectRoot.count + 1))
                } else {
                    // File is outside the project — use absolute path
                    sourceTree = .absolute
                    relativePath = resolvedFilePath
                }

                let fileExtension = URL(fileURLWithPath: resolvedFilePath).pathExtension
                let newRef = PBXFileReference(
                    sourceTree: sourceTree,
                    name: fileName,
                    lastKnownFileType: Xcode.filetype(extension: fileExtension),
                    path: relativePath,
                )
                xcodeproj.pbxproj.add(object: newRef)
                fileReference = newRef
            }

            // Add file to group if not already present
            if !targetGroup.children.contains(where: { $0 === fileReference }) {
                targetGroup.children.append(fileReference)
            }

            // Add file to target if specified
            if let targetName {
                guard
                    let target = xcodeproj.pbxproj.nativeTargets.first(where: {
                        $0.name == targetName
                    })
                else {
                    throw MCPError.invalidParams("Target '\(targetName)' not found in project")
                }

                // Create build file
                let buildFile = PBXBuildFile(file: fileReference)
                xcodeproj.pbxproj.add(object: buildFile)

                // Add to appropriate build phase based on file extension
                let fileExtension = URL(fileURLWithPath: resolvedFilePath).pathExtension
                    .lowercased()

                if ["swift", "m", "mm", "c", "cpp", "cc", "cxx"].contains(fileExtension) {
                    // Source file - add to compile sources
                    if let sourcesBuildPhase = target.buildPhases.first(where: {
                        $0 is PBXSourcesBuildPhase
                    }) as? PBXSourcesBuildPhase {
                        sourcesBuildPhase.files = (sourcesBuildPhase.files ?? []) + [buildFile]
                    } else {
                        let sourcesBuildPhase = PBXSourcesBuildPhase(files: [buildFile])
                        xcodeproj.pbxproj.add(object: sourcesBuildPhase)
                        target.buildPhases.append(sourcesBuildPhase)
                    }
                } else if ["h", "hpp", "hxx"].contains(fileExtension) {
                    // Header file - add to headers build phase
                    if let headersBuildPhase = target.buildPhases.first(where: {
                        $0 is PBXHeadersBuildPhase
                    }) as? PBXHeadersBuildPhase {
                        headersBuildPhase.files = (headersBuildPhase.files ?? []) + [buildFile]
                    } else {
                        let headersBuildPhase = PBXHeadersBuildPhase(files: [buildFile])
                        xcodeproj.pbxproj.add(object: headersBuildPhase)
                        target.buildPhases.append(headersBuildPhase)
                    }
                } else {
                    // Resource file - add to copy bundle resources
                    if let resourcesBuildPhase = target.buildPhases.first(where: {
                        $0 is PBXResourcesBuildPhase
                    }) as? PBXResourcesBuildPhase {
                        resourcesBuildPhase.files =
                            (resourcesBuildPhase.files ?? []) + [buildFile]
                    } else {
                        let resourcesBuildPhase = PBXResourcesBuildPhase(files: [buildFile])
                        xcodeproj.pbxproj.add(object: resourcesBuildPhase)
                        target.buildPhases.append(resourcesBuildPhase)
                    }
                }
            }

            // Write project
            try PBXProjWriter.write(xcodeproj, to: Path(projectURL.path))

            let targetInfo = targetName != nil ? " to target '\(targetName!)'" : ""
            let groupInfo = groupName != nil ? " in group '\(groupName!)'" : ""

            return CallTool.Result(
                content: [
                    .text(
                        text: "Successfully added file '\(fileName)'\(targetInfo)\(groupInfo)",
                        annotations: nil,
                        _meta: nil,
                    ),
                ],
            )
        } catch {
            throw MCPError.internalError(
                "Failed to add file to Xcode project: \(error.localizedDescription)",
            )
        }
    }
}
