import MCP
import PathKit
import XCMCPCore
import XcodeProj
import Foundation

public struct RemoveFolderTool: Sendable {
    private let pathUtility: PathUtility

    public init(pathUtility: PathUtility) { self.pathUtility = pathUtility }

    public func tool() -> Tool {
        .init(
            name: "remove_synchronized_folder",
            description:
                "Remove a synchronized folder reference from an Xcode project (does not delete the folder from disk)",
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
                            "Path of the synchronized folder to remove (e.g., 'Core' or 'Core/Sources')",
                        ),
                    ]),
                ]),
                "required": .array([.string("project_path"), .string("folder_path")]),
            ]),
            annotations: .destructive,
        )
    }

    public func execute(arguments: [String: Value]) throws -> CallTool.Result {
        guard let projectPath = arguments.getString("project_path"),
              let folderPath = arguments.getString("folder_path")
        else { throw MCPError.invalidParams("project_path and folder_path are required") }

        do {
            // Resolve and validate the project path
            let resolvedProjectPath = try pathUtility.resolvePath(from: projectPath)
            let projectURL = URL(filePath: resolvedProjectPath)

            let preimage = PBXProjWriter.preimage(of: Path(projectURL.path))
            let xcodeproj = try XcodeProj(path: Path(projectURL.path))

            // Get the root project and main group
            guard let project = try xcodeproj.pbxproj.rootProject(),
                let mainGroup = project.mainGroup
            else { throw MCPError.internalError("Main group not found in project") }

            // Find the synchronized folder. The utility matches a leaf path, a full path, or a
            // trailing suffix of one, and it reports a leaf two folders share.
            let match: SynchronizedFolderUtility.Match

            switch SynchronizedFolderUtility.lookUpSyncGroup(
                folderPath: folderPath, target: nil, in: mainGroup,
            ) {
                case .none:
                    return CallTool.Result.text(
                        "Synchronized folder not found in project: \(folderPath)")
                case let .ambiguous(paths):
                    throw MCPError.invalidParams(SynchronizedFolderUtility.ambiguityMessage(
                        folderPath: folderPath, paths: paths))
                case let .one(found): match = found
            }

            guard let parent = xcodeproj.pbxproj.groups.first(where: { group in
                group.children.contains { $0 === match.group }
            }) else {
                throw MCPError.internalError(
                    "Synchronized folder '\(match.fullPath)' has no parent group")
            }

            // Remove any associated exception sets and build files
            removeAssociatedObjects(for: match.group, in: xcodeproj)
            parent.children.removeAll { $0 === match.group }

            try PBXProjWriter.write(
                xcodeproj, to: Path(projectURL.path), expectedPreimage: preimage)

            return CallTool.Result.text(
                "Successfully removed synchronized folder '\(match.fullPath)' from project")
        } catch {
            throw try error.asMCPError()
        }
    }

    private func removeAssociatedObjects(
        for syncGroup: PBXFileSystemSynchronizedRootGroup,
        in xcodeproj: XcodeProj,
    ) {
        // Remove any build files referencing this synchronized folder
        let buildFilesToRemove = xcodeproj.pbxproj.buildFiles.filter { buildFile in
            buildFile.file === syncGroup
        }

        for buildFile in buildFilesToRemove {
            // Remove from build phases
            for target in xcodeproj.pbxproj.nativeTargets {
                for phase in target.buildPhases { phase.files?.removeAll { $0 === buildFile } }
            }
            xcodeproj.pbxproj.delete(object: buildFile)
        }

        // Drop the target links. A target that keeps the id in fileSystemSynchronizedGroups holds a
        // dangling reference once the group object goes, and the write gate refuses that file.
        for target in xcodeproj.pbxproj.nativeTargets {
            guard let groups = target.fileSystemSynchronizedGroups else { continue }
            let remaining = groups.filter { $0 !== syncGroup }
            guard remaining.count != groups.count else { continue }
            target.fileSystemSynchronizedGroups = remaining.isEmpty ? nil : remaining
        }

        // Drop the exception sets the group owns, which nothing references once it goes
        for exception in syncGroup.exceptions ?? [] { xcodeproj.pbxproj.delete(object: exception) }
        syncGroup.exceptions = nil

        // Remove the synchronized group object itself
        xcodeproj.pbxproj.delete(object: syncGroup)
    }
}
