import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

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
                            "Path to the .xcodeproj file (relative to current directory)",
                        ),
                    ]),
                    "folder_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Path to the folder to add (relative to project root or absolute)",
                        ),
                    ]),
                    "group_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the group to add the folder to (optional, defaults to main group)",
                        ),
                    ]),
                    "target_name": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Name of the target to add the folder to (optional)",
                        ),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("folder_path")]),
            ]),
            annotations: .mutation,
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
                atPath: resolvedFolderPath, isDirectory: &isDirectory,
            ) {
                throw MCPError.invalidParams("Folder does not exist at path: \(folderPath)")
            }
            if !isDirectory.boolValue {
                throw MCPError.invalidParams("Path is not a directory: \(folderPath)")
            }

            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Find the group to add the folder to (must be done before calculating relative path)
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

            // Create file system synchronized root group
            let folderName = URL(filePath: resolvedFolderPath).lastPathComponent

            // Compute the path relative to the parent group. Since `sourceTree = <group>`,
            // Xcode resolves the synchronized folder's `path` attribute relative to its
            // parent group's accumulated path. We walk up the group chain ourselves
            // (rather than relying on `fullPath()`, which silently returns nil when the
            // chain has any unset `parent` reference or non-.group `sourceTree`) and trim
            // the redundant prefix. This matches the path attribute Xcode emits when you
            // add the folder through the IDE.
            let projectRoot = projectURL.deletingLastPathComponent().path
            let parentRelativePath = parentGroupPathFromProjectRoot(
                of: targetGroup, pbxproj: xcodeproj.pbxproj,
            )
            let folderRelativeToProject: String =
                pathUtility.makeRelativePath(from: resolvedFolderPath)
                ?? makeRelative(absolute: resolvedFolderPath, base: projectRoot)
                ?? resolvedFolderPath

            let relativePath: String
            if !parentRelativePath.isEmpty,
               folderRelativeToProject == parentRelativePath
            {
                relativePath = "."
            } else if !parentRelativePath.isEmpty,
                      folderRelativeToProject.hasPrefix(parentRelativePath + "/")
            {
                relativePath = String(
                    folderRelativeToProject.dropFirst(parentRelativePath.count + 1),
                )
            } else {
                relativePath = folderRelativeToProject
            }

            let folderReference = PBXFileSystemSynchronizedRootGroup(
                sourceTree: .group,
                path: relativePath,
                name: folderName,
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
                    .text(text:
                        "Successfully added folder reference '\(folderName)'\(targetInfo)\(groupInfo)",
                        annotations: nil, _meta: nil),
                ],
            )
        } catch {
            throw MCPError.internalError(
                "Failed to add folder to Xcode project: \(error.localizedDescription)",
            )
        }
    }

    /// Walks up the group hierarchy from `group` to the project's main group,
    /// accumulating the `path` attributes of `.group`-sourceTree ancestors. Returns
    /// the project-root-relative path that the parent group's children inherit
    /// (an empty string if the chain contributes no on-disk path component).
    ///
    /// Unlike XcodeProj's `fullPath(sourceRoot:)`, this does not require parent
    /// references to be wired up — it scans the `groups` collection to find
    /// each ancestor — and it returns an empty string (not nil) when the chain
    /// is purely virtual, so callers can branch on whether trimming applies.
    private func parentGroupPathFromProjectRoot(
        of group: PBXGroup, pbxproj: PBXProj,
    ) -> String {
        let mainGroup = try? pbxproj.rootProject()?.mainGroup
        if let mainGroup, group === mainGroup { return "" }

        var components: [String] = []
        var current: PBXGroup? = group
        var visited = Set<ObjectIdentifier>()

        while let g = current {
            if let mg = mainGroup, g === mg { break }
            let id = ObjectIdentifier(g)
            if visited.contains(id) { break }
            visited.insert(id)

            if g.sourceTree == .group || g.sourceTree == nil,
               let p = g.path, !p.isEmpty
            {
                components.insert(p, at: 0)
            }

            current = pbxproj.groups.first(where: { candidate in
                candidate.children.contains { $0 === g }
            })
        }

        return components.joined(separator: "/")
    }

    /// Fallback when `PathUtility.makeRelativePath` returns nil (e.g. when the
    /// project lives outside the configured base path). Computes a simple
    /// relative path by prefix-matching.
    private func makeRelative(absolute: String, base: String) -> String? {
        let normalizedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        if absolute == normalizedBase { return "" }
        if absolute.hasPrefix(normalizedBase + "/") {
            return String(absolute.dropFirst(normalizedBase.count + 1))
        }
        return nil
    }
}
